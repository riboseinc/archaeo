# frozen_string_literal: true

module Archaeo
  # Model representing the outcome of a SavePageNow request.
  #
  # Contains the resulting archive URL, timestamp, and whether
  # the page was already cached in the archive.
  class SaveResult
    attr_reader :url, :archive_url, :timestamp

    def initialize(url:, archive_url:, timestamp:, cached:)
      @url = url
      @archive_url = archive_url
      @timestamp = timestamp ? Timestamp.coerce(timestamp) : nil
      @cached = cached
    end

    def cached?
      @cached
    end

    def success?
      !@archive_url.nil?
    end

    def to_h
      { url: @url, archive_url: @archive_url,
        timestamp: @timestamp, cached: @cached }
    end

    def as_json(*)
      { url: @url, archive_url: @archive_url,
        timestamp: @timestamp.to_s, cached: @cached }
    end

    def to_s
      label = @cached ? "Cached" : "Saved"
      "#{label}: #{@archive_url}"
    end

    def inspect
      "#<#{self.class.name} #{@url} cached=#{@cached}>"
    end
  end
end
