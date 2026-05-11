# frozen_string_literal: true

module Archaeo
  # Model representing the result of an availability query.
  #
  # Indicates whether a URL is archived and, if so, provides
  # the closest snapshot's archive URL and timestamp.
  class AvailabilityResult
    attr_reader :url, :archive_url, :timestamp, :archived_status

    def initialize(url:, available:, archive_url: nil,
                   timestamp: nil, archived_status: nil)
      @url = url
      @available = available
      @archive_url = archive_url
      @timestamp = timestamp
      @archived_status = archived_status
    end

    def available?
      @available
    end

    def unavailable?
      !@available
    end

    def to_s
      if available?
        "#{url} -> #{archive_url} (#{timestamp})"
      else
        "#{url} -> not available"
      end
    end

    def to_h
      {
        url: @url,
        available: @available,
        archive_url: @archive_url,
        timestamp: @timestamp,
        archived_status: @archived_status,
      }
    end

    def as_json(*)
      {
        url: @url,
        available: @available,
        archive_url: @archive_url,
        timestamp: @timestamp&.to_s,
        archived_status: @archived_status,
      }
    end

    def inspect
      "#<#{self.class.name} #{@url} available=#{@available}>"
    end

    def to_snapshot
      return nil unless available?

      Snapshot.new(
        urlkey: UrlNormalizer.normalize(url).downcase,
        timestamp: timestamp,
        original_url: url,
        status_code: archived_status || 200,
      )
    end
  end
end
