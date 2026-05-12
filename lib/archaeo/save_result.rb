# frozen_string_literal: true

module Archaeo
  # Model representing the outcome of a SavePageNow request.
  #
  # Contains the resulting archive URL, timestamp, whether
  # the page was already cached, and response metadata.
  class SaveResult
    attr_reader :url, :archive_url, :timestamp, :status_code,
                :response_url, :response_headers

    def initialize(url:, archive_url:, timestamp:, cached:,
                   status_code: nil, response_url: nil,
                   response_headers: nil)
      @url = url
      @archive_url = archive_url
      @timestamp = timestamp ? Timestamp.coerce(timestamp) : nil
      @cached = cached
      @status_code = status_code
      @response_url = response_url
      @response_headers = response_headers
    end

    def cached?
      @cached
    end

    def success?
      !@archive_url.nil?
    end

    def to_h
      {
        url: @url,
        archive_url: @archive_url,
        timestamp: @timestamp,
        cached: @cached,
        status_code: @status_code,
        response_url: @response_url,
      }
    end

    def as_json(*)
      {
        url: @url,
        archive_url: @archive_url,
        timestamp: @timestamp.to_s,
        cached: @cached,
        status_code: @status_code,
        response_url: @response_url,
      }
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
