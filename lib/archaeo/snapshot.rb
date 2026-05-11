# frozen_string_literal: true

module Archaeo
  # A single CDX Server API record representing an archived document.
  #
  # Maps the seven standard CDX fields and provides the computed
  # archive URL via the ArchiveUrl model.
  class Snapshot
    FIELDS = %i[urlkey timestamp original_url
                mimetype status_code digest length].freeze

    BLOCKED_STATUS = -1

    attr_reader(*FIELDS)

    def initialize(urlkey:, timestamp:, original_url:,
                   mimetype: nil, status_code: nil,
                   digest: nil, length: nil)
      @urlkey = urlkey.to_s
      @timestamp = Timestamp.coerce(timestamp)
      @original_url = original_url.to_s
      @mimetype = mimetype.to_s
      @status_code = status_code.to_i
      @digest = digest.to_s
      @length = length.to_i
    end

    def archive_url
      ArchiveUrl.new(original_url, timestamp: @timestamp).to_s
    end

    def identity_url
      ArchiveUrl.new(original_url, timestamp: @timestamp,
                                   identity: true).to_s
    end

    def blocked?
      @status_code == BLOCKED_STATUS
    end

    def success?
      @status_code == 200
    end

    def redirect?
      @status_code.between?(300, 399)
    end

    def client_error?
      @status_code.between?(400, 499)
    end

    def server_error?
      @status_code.between?(500, 599)
    end

    def error?
      client_error? || server_error?
    end

    def age
      Time.now - @timestamp.to_time
    end

    def older_than?(seconds)
      age > seconds
    end

    def newer_than?(seconds)
      age <= seconds
    end

    def same_content_as?(other)
      return false unless other.is_a?(self.class)
      return false if digest.nil? || digest.empty?
      return false if other.digest.nil? || other.digest.empty?

      digest == other.digest
    end

    def duplicate_of?(other)
      same_content_as?(other) && timestamp != other.timestamp
    end

    def fetch(client: HttpClient.new, identity: false)
      Fetcher.new(client: client).fetch(
        original_url, timestamp: @timestamp, identity: identity
      )
    end

    def fetch_with_assets(client: HttpClient.new)
      Fetcher.new(client: client).fetch_page_with_assets(
        original_url, timestamp: @timestamp
      )
    end

    def to_a
      [@urlkey, @timestamp, @original_url, @mimetype,
       @status_code, @digest, @length]
    end

    def to_h
      {
        urlkey: @urlkey,
        timestamp: @timestamp,
        original_url: @original_url,
        mimetype: @mimetype,
        status_code: @status_code,
        digest: @digest,
        length: @length,
      }
    end

    def as_json(*)
      {
        urlkey: @urlkey,
        timestamp: @timestamp.to_s,
        original_url: @original_url,
        mimetype: @mimetype,
        status_code: @status_code,
        digest: @digest,
        length: @length,
      }
    end

    def ==(other)
      other.is_a?(self.class) && to_a == other.to_a
    end
    alias_method :eql?, :==

    def hash
      to_a.hash
    end

    def inspect
      "#<#{self.class.name} #{timestamp} " \
        "#{original_url} status=#{status_code}>"
    end
  end
end
