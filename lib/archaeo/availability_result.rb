# frozen_string_literal: true

module Archaeo
  # Model representing the result of an availability query.
  #
  # Indicates whether a URL is archived and, if so, provides
  # the closest snapshot's archive URL and timestamp.
  class AvailabilityResult
    attr_reader :url, :archive_url, :timestamp

    def initialize(url:, available:, archive_url: nil, timestamp: nil)
      @url = url
      @available = available
      @archive_url = archive_url
      @timestamp = timestamp
    end

    def available?
      @available
    end
  end
end
