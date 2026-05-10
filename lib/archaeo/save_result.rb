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
      @timestamp = Timestamp.coerce(timestamp)
      @cached = cached
    end

    def cached?
      @cached
    end
  end
end
