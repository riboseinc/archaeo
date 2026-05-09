# frozen_string_literal: true

module Archaeo
  # A single CDX Server API record representing an archived document.
  #
  # Maps the seven standard CDX fields and provides the computed
  # archive URL via the ArchiveUrl model.
  class Snapshot
    FIELDS = %i[urlkey timestamp original_url
                mimetype status_code digest length].freeze

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

    def ==(other)
      other.is_a?(self.class) &&
        FIELDS.all? { |f| send(f) == other.send(f) }
    end
    alias_method :eql?, :==

    def hash
      FIELDS.map { |f| send(f) }.hash
    end
  end
end
