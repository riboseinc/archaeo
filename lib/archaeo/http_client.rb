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
                   user_agent: nil)
      @timeout = timeout
      @max_retries = max_retries
      @retry_delay = retry_delay
      @user_agent = user_agent
      @connections = {}
      @mutex = Mutex.new
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
        @connections.each_value do |http|
          http.finish
        rescue StandardError
          nil
        end
        @connections.clear
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
        http = @connections[key]
        if http && !http.active?
          @connections.delete(key)
          http = nil
        end
        @connections[key] = build_connection(uri) unless http
        @connections[key]
      end
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
      @mutex.synchronize do
        http = @connections.delete(key)
        begin
          http&.finish
        rescue StandardError
          nil
        end
      end
    end

    def attempt_with_retries(uri, headers, request_class)
      retries = 0
      begin
        execute_with_connection(uri, headers, request_class)
      rescue *TRANSIENT_ERRORS => e
        retries += 1
        raise_if_exhausted(retries, e)
        invalidate_connection(uri)
        sleep(@retry_delay * retries)
        retry
      end
    end

    def raise_if_exhausted(retries, error)
      return unless retries > @max_retries

      raise MaximumRetriesExceeded,
            "Failed after #{retries} retries: #{error.message}"
    end

    def execute_with_connection(uri, headers, request_class)
      http = connection_for(uri)
      request = request_class.new(uri)
      headers.each { |k, v| request[k] = v }
      raw = http.request(request)
      build_response(raw)
    rescue *TRANSIENT_ERRORS
      raise
    rescue StandardError
      invalidate_connection(uri)
      raise
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
