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

      AvailabilityResult.new(
        url: url,
        available: closest["status"].to_s == "200",
        archive_url: archive_url,
        timestamp: ts,
      )
    end
  end
end
