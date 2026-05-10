# frozen_string_literal: true

require "net/http"
require "uri"
require "zlib"
require "stringio"

module Archaeo
  # HTTP client with retry logic, gzip decompression,
  # rotating realistic User-Agent profiles, and connection pooling.
  #
  # Injected via constructor for testability. Connections are reused
  # across requests to the same host for improved performance.
  class HttpClient
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 3
    DEFAULT_RETRY_DELAY = 2
    MAX_POOL_SIZE = 8
    MAX_IDLE_TIME = 60

    RETRIABLE_STATUSES = [429, 502, 503, 504].freeze

    TRANSIENT_ERRORS = [
      Net::ReadTimeout,
      Net::OpenTimeout,
      IOError,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      EOFError,
      Errno::EPIPE,
    ].freeze

    USER_AGENT_PROFILES = [
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
      "AppleWebKit/537.36 (KHTML, like Gecko) " \
      "Chrome/131.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " \
      "AppleWebKit/537.36 (KHTML, like Gecko) " \
      "Chrome/130.0.0.0 Safari/537.36",
      "Mozilla/5.0 (X11; Linux x86_64) " \
      "AppleWebKit/537.36 (KHTML, like Gecko) " \
      "Chrome/131.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
      "AppleWebKit/537.36 (KHTML, like Gecko) " \
      "Chrome/129.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " \
      "AppleWebKit/537.36 (KHTML, like Gecko) " \
      "Chrome/131.0.0.0 Safari/537.36",
    ].freeze

    # HTTP response with status code, headers (lowercase keys), and body.
    class Response
      attr_reader :status, :headers, :body

      def initialize(status:, headers:, body:)
        @status = status
        @headers = headers
        @body = body
      end
    end

    def initialize(timeout: DEFAULT_TIMEOUT,
                   max_retries: DEFAULT_MAX_RETRIES,
                   retry_delay: DEFAULT_RETRY_DELAY,
                   user_agent: nil,
                   on_request: nil)
      @timeout = timeout
      @max_retries = max_retries
      @retry_delay = retry_delay
      @user_agent = user_agent
      @on_request = on_request
      @connections = {}
      @last_used = {}
      @mutex = Mutex.new
      @shutdown = false
    end

    def self.open(**opts)
      client = new(**opts)
      yield client
    ensure
      client&.shutdown
    end

    def get(url, headers: {})
      merged = default_headers.merge(headers)
      uri = URI(url)
      attempt_with_retries(uri, merged, Net::HTTP::Get)
    end

    def head(url, headers: {})
      merged = default_headers.merge(headers)
      uri = URI(url)
      attempt_with_retries(uri, merged, Net::HTTP::Head)
    end

    def shutdown
      @mutex.synchronize do
        return if @shutdown

        @shutdown = true
        @connections.each_value do |http|
          http.finish
        rescue StandardError
          nil
        end
        @connections.clear
      end
    end

    def pool_stats
      now = Time.now
      @mutex.synchronize do
        {
          active_connections: @connections.size,
          max_pool_size: MAX_POOL_SIZE,
          hosts: @connections.keys,
          idle_times: @last_used.transform_values { |t| (now - t).round },
        }.freeze
      end
    end

    private

    def select_user_agent
      @user_agent || USER_AGENT_PROFILES.sample
    end

    def connection_key(uri)
      "#{uri.scheme}://#{uri.host}:#{uri.port}"
    end

    def connection_for(uri)
      key = connection_key(uri)
      @mutex.synchronize do
        evict_if_pool_full(key)
        http = @connections[key]
        if http && !http.active?
          close_connection(key)
          http = nil
        end
        @connections[key] = build_connection(uri) unless http
        @last_used[key] = Time.now
        @connections[key]
      end
    end

    def evict_if_pool_full(key)
      evict_stale_connections
      return unless @connections.size >= MAX_POOL_SIZE &&
        !@connections.key?(key)

      evict_lru
    end

    def build_connection(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = @timeout
      http.open_timeout = @timeout
      http.start
      http
    end

    def invalidate_connection(uri)
      key = connection_key(uri)
      @mutex.synchronize { close_connection(key) }
    end

    def close_connection(key)
      http = @connections.delete(key)
      @last_used.delete(key)
      begin
        http&.finish
      rescue StandardError
        nil
      end
    end

    def evict_stale_connections
      now = Time.now
      @connections.each_key do |key|
        idle = now - (@last_used[key] || now)
        close_connection(key) if idle > MAX_IDLE_TIME
      end
    end

    def evict_lru
      lru_key = @last_used.min_by { |_, t| t }&.first
      close_connection(lru_key) if lru_key
    end

    # Internal error class for HTTP status retry signaling
    class RetriableStatusError < StandardError
      attr_reader :response

      def initialize(response)
        @response = response
        super("Retriable HTTP status: #{response.status}")
      end
    end

    def attempt_with_retries(uri, headers, request_class)
      retries = 0
      begin
        execute_and_check(uri, headers, request_class)
      rescue RetriableStatusError => e
        retry_status(e, retries += 1) && retry
      rescue *TRANSIENT_ERRORS => e
        retry_transient(e, uri, retries += 1) && retry
      end
    end

    def retry_status(error, retries)
      raise_if_exhausted(retries,
                         RateLimitError.new("HTTP #{error.response.status}"))
      sleep(extract_retry_after(error.response) || (@retry_delay * retries))
    end

    def retry_transient(error, uri, retries)
      raise_if_exhausted(retries, error)
      invalidate_connection(uri)
      sleep(@retry_delay * retries)
    end

    def execute_and_check(uri, headers, request_class)
      response = execute_with_connection(uri, headers, request_class)
      if RETRIABLE_STATUSES.include?(response.status)
        raise RetriableStatusError, response
      end

      response
    end

    def extract_retry_after(response)
      value = response.headers["retry-after"]
      return nil unless value

      Integer(value)
    rescue ArgumentError
      parse_retry_after_date(value)
    end

    def parse_retry_after_date(value)
      remaining = (Time.httpdate(value) - Time.now).to_i
      [remaining, 0].max
    rescue ArgumentError
      nil
    end

    def raise_if_exhausted(retries, error)
      return unless retries > @max_retries

      raise MaximumRetriesExceeded,
            "Failed after #{retries} retries: #{error.message}"
    end

    def execute_with_connection(uri, headers, request_class)
      request = build_request(uri, headers, request_class)
      execute_tracked_request(uri, request)
    rescue *TRANSIENT_ERRORS
      raise
    rescue StandardError
      invalidate_connection(uri)
      raise
    end

    def build_request(uri, headers, request_class)
      request = request_class.new(uri)
      headers.each { |k, v| request[k] = v }
      request
    end

    def execute_tracked_request(uri, request)
      http = connection_for(uri)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw = http.request(request)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      response = build_response(raw)
      @on_request&.call(uri, elapsed, response.status, 0)
      response
    end

    def default_headers
      {
        "User-Agent" => select_user_agent,
        "Accept" => "text/html,application/xhtml+xml," \
                    "application/xml;q=0.9,*/*;q=0.8",
        "Accept-Encoding" => "gzip",
        "Accept-Language" => "en-US,en;q=0.9",
        "Connection" => "keep-alive",
      }
    end

    def build_response(raw)
      headers = raw.each_header.to_h { |k, v| [k.downcase, v] }
      Response.new(
        status: raw.code.to_i,
        headers: headers,
        body: decompress_body(raw),
      )
    end

    def decompress_body(raw)
      body = raw.body.to_s
      return body unless raw["content-encoding"] == "gzip" && !body.empty?

      Zlib::GzipReader.new(StringIO.new(body)).read
    rescue Zlib::GzipFile::Error
      body
    end
  end
end
