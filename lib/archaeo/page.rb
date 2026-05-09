# frozen_string_literal: true

module Archaeo
  # Model representing a fetched archived page from the Wayback Machine.
  #
  # Contains the page content, metadata, and provenance information
  # for a single archived resource.
  class Page
    attr_reader :content, :content_type, :status_code,
                :archive_url, :original_url, :timestamp

    def initialize(content:, content_type:, status_code:,
                   archive_url:, original_url:, timestamp:)
      @content = content
      @content_type = content_type
      @status_code = status_code
      @archive_url = archive_url
      @original_url = original_url
      @timestamp = Timestamp.coerce(timestamp)
    end
  end
end
