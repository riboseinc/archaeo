# frozen_string_literal: true

require "json"
require "uri"

module Archaeo
  # Client for the Wayback Machine Availability API.
  #
  # Check whether a URL has been archived and retrieve the closest
  # available snapshot for a given point in time.
  class AvailabilityApi
    ENDPOINT = "https://archive.org/wayback/available"

    def initialize(client: HttpClient.new)
      @client = client
    end

    def near(url, timestamp: nil)
      url = UrlNormalizer.normalize(url)
      params = { "url" => url }
      params["timestamp"] = timestamp.to_s if timestamp

      response = @client.get(
        "#{ENDPOINT}?#{URI.encode_www_form(params)}",
      )
      parse_response(response, url)
    end

    def oldest(url)
      near(url, timestamp: Timestamp.new(year: 1994, month: 1, day: 1))
    end

    def newest(url)
      near(url, timestamp: Timestamp.now)
    end

    def available?(url)
      near(url).available?
    end

    def batch_available?(urls, concurrency: 1)
      if concurrency <= 1
        urls.to_h do |u|
          [u, near(u)]
        end
      else
        batch_concurrent(urls, concurrency)
      end
    end

    private

    def parse_response(response, url)
      unless response.status == 200
        if response.status == 503
          raise RateLimitError,
                "Availability API rate limited (HTTP 503)"
        end

        raise InvalidResponse,
              "Availability API returned HTTP #{response.status}"
      end

      json = JSON.parse(response.body)
      snapshots = json["archived_snapshots"]
      return unavailable(url) if snapshots.nil? || snapshots.empty?

      closest = snapshots["closest"]
      return unavailable(url) if closest.nil?

      build_result(closest, url)
    end

    def unavailable(url)
      AvailabilityResult.new(url: url, available: false)
    end

    def build_result(closest, url)
      archive_url = closest["url"].to_s.sub(%r{^http://}, "https://")
      ts = Timestamp.parse(closest["timestamp"])
      archived_status = closest["status"].to_i

      AvailabilityResult.new(
        url: url,
        available: true,
        archive_url: archive_url,
        timestamp: ts,
        archived_status: archived_status,
      )
    end

    def batch_concurrent(urls, concurrency)
      results = {}
      mutex = Mutex.new
      queue = urls.dup
      threads = Array.new(concurrency) do
        Thread.new { drain_queue(queue, results, mutex) }
      end
      threads.each(&:join)
      results
    end

    def drain_queue(queue, results, mutex)
      loop do
        url = mutex.synchronize { queue.shift }
        break unless url

        result = near(url)
        mutex.synchronize { results[url] = result }
      end
    end
  end
end
