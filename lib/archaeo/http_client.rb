# frozen_string_literal: true

require "net/http"
require "uri"
require "zlib"
require "stringio"

module Archaeo
  # HTTP client with retry logic, gzip decompression, and
  # rotating realistic User-Agent profiles.
  #
  # Injected via constructor for testability.
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
    end

    def get(url, headers: {})
      merged = default_headers.merge(headers)
      attempt_with_retries(url, merged)
    end

    private

    def select_user_agent
      @user_agent || USER_AGENT_PROFILES.sample
    end

    def attempt_with_retries(url, headers)
      retries = 0
      begin
        execute_get(url, headers)
      rescue *TRANSIENT_ERRORS => e
        retries += 1
        raise_if_exhausted(retries, e)
        sleep(@retry_delay * retries)
        retry
      end
    end

    def raise_if_exhausted(retries, error)
      return unless retries > @max_retries

      raise MaximumRetriesExceeded,
            "Failed after #{retries} retries: #{error.message}"
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

    def execute_get(url, headers)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == "https",
                      read_timeout: @timeout,
                      open_timeout: @timeout) do |http|
        request = Net::HTTP::Get.new(uri)
        headers.each { |k, v| request[k] = v }
        raw = http.request(request)
        build_response(raw)
      end
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
