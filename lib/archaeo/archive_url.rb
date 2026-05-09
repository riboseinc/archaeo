# frozen_string_literal: true

module Archaeo
  # Model representing a Wayback Machine archive URL.
  #
  # Encapsulates URL construction and parsing for archive.org URLs,
  # supporting both normal and identity (raw) modes.
  class ArchiveUrl
    BASE = "https://web.archive.org/web"

    TIMESTAMP_RE = %r{web\.archive\.org/web/(\d{14})}

    attr_reader :original_url, :timestamp

    def initialize(original_url, timestamp:, identity: false)
      @original_url = original_url.to_s
      @timestamp = Timestamp.coerce(timestamp)
      @identity = identity
    end

    def self.parse(string)
      match = string.match(TIMESTAMP_RE)
      unless match
        raise ArgumentError,
              "Not a valid archive URL: #{string}"
      end

      ts = Timestamp.parse(match[1])
      identity = string.include?("#{match[1]}id_/")
      rest = extract_original_url(string, match[1], identity)

      new(rest, timestamp: ts, identity: identity)
    end

    def identity?
      @identity
    end

    def to_s
      suffix = identity? ? "id_" : ""
      "#{BASE}/#{@timestamp}#{suffix}/#{@original_url}"
    end

    def self.extract_original_url(string, ts_str, identity)
      marker = identity ? "#{ts_str}id_/" : "#{ts_str}/"
      idx = string.index(marker)
      return "" unless idx

      string[(idx + marker.length)..]
    end

    private_class_method :extract_original_url
  end
end
