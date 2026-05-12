# frozen_string_literal: true

module Archaeo
  # Client for the Wayback Machine SavePageNow (SPN) API.
  #
  # Request the Wayback Machine to archive a URL and retrieve the
  # resulting archive URL and timestamp as a SaveResult.
  class SaveApi
    ENDPOINT = "https://web.archive.org/save"
    DEFAULT_MAX_TRIES = 8
    TIMESTAMP_RE = %r{web\.archive\.org/web/(\d{14})}

    def initialize(client: HttpClient.new,
                   max_tries: DEFAULT_MAX_TRIES,
                   rate_limiter: nil)
      @client = client
      @max_tries = max_tries
      @rate_limiter = rate_limiter
    end

    def save(url)
      url = UrlNormalizer.normalize(url)
      save_url = "#{ENDPOINT}/#{url}"
      start_time = Time.now.utc
      attempt_save(save_url, start_time, url)
    end

    def batch_save(urls, delay: 2, stop_on_error: false)
      results = []
      urls.each_with_index do |url, i|
        sleep(delay) if i.positive?
        result = save(url)
        results << result
      rescue RateLimitError, SaveFailed => e
        raise e if stop_on_error

        results << SaveResult.new(
          url: url, archive_url: nil, timestamp: nil, cached: false,
        )
      end
      results
    end

    private

    def attempt_save(save_url, start_time, url)
      @max_tries.times do |attempt|
        sleep(retry_delay(attempt)) if attempt.positive?
        @rate_limiter&.wait(host: "web.archive.org")

        response = @client.get(save_url)
        check_response_errors!(response, url)

        result = process_save_response(response, start_time, url)
        return result if result
      end

      raise MaximumRetriesExceeded,
            "Failed to save #{url} after #{@max_tries} attempts"
    end

    def process_save_response(response, start_time, url)
      archive_url = extract_archive_url(response)
      return nil unless archive_url

      ts = Timestamp.parse(extract_timestamp(archive_url))
      cached = ts.to_time < start_time - 2700
      SaveResult.new(
        url: url, archive_url: archive_url,
        timestamp: ts, cached: cached,
        status_code: response.status,
        response_url: response.headers["location"],
        response_headers: response.headers
      )
    end

    def check_response_errors!(response, url)
      case response.status
      when 429
        raise RateLimitError, "Rate limited while saving #{url}"
      when 509
        raise SaveFailed, "Session limit reached while saving #{url}"
      end
    end

    def retry_delay(attempt)
      ((attempt + 1) % 3).zero? ? 10 : 5
    end

    def extract_archive_url(response)
      headers = response.headers
      from_content_location(headers) ||
        from_memento_link(headers) ||
        from_cache_key(headers) ||
        from_location(headers)
    end

    def from_content_location(headers)
      location = headers["content-location"]
      return unless location&.match?(%r{^/web/\d{14}/})

      "https://web.archive.org#{location}"
    end

    def from_memento_link(headers)
      link = headers["link"].to_s
      match = link.match(
        %r{rel="memento".*?href="(web\.archive\.org/web/\d{14}/.*?)"},
      )
      return unless match

      "https://#{match[1]}"
    end

    def from_cache_key(headers)
      cache_key = headers["x-cache-key"].to_s
      match = cache_key.match(/(https.*)[A-Z]{2}/)
      match ? match[1] : nil
    end

    def from_location(headers)
      location = headers["location"].to_s
      match = location.match(%r{(web\.archive\.org/web/\d+/.*)$})
      return unless match

      "https://#{match[1]}"
    end

    def extract_timestamp(archive_url)
      match = archive_url.match(TIMESTAMP_RE)
      return match[1] if match

      raise InvalidResponse,
            "Cannot parse timestamp from: #{archive_url}"
    end
  end
end
