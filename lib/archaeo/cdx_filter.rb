# frozen_string_literal: true

module Archaeo
  # Builds and validates CDX Server API filter expressions.
  #
  # CDX filter format: [!]field:regex
  # The optional ! prefix inverts the match. The field must be a
  # recognized CDX field name. The regex is a Java-compatible
  # regex pattern matched against the field value.
  class CdxFilter
    VALID_FIELDS = %w[
      urlkey timestamp original mimetype statuscode
      digest length
    ].freeze

    def initialize(expression)
      @expression = expression.to_s
      validate!
    end

    def to_s
      @expression
    end

    def negated?
      @expression.start_with?("!")
    end

    def field
      stripped = @expression.delete_prefix("!")
      stripped.split(":", 2).first.to_s
    end

    def self.by_status(code)
      new("statuscode:#{code}")
    end

    def self.excluding_status(code)
      new("!statuscode:#{code}")
    end

    def self.by_mimetype(type)
      new("mimetype:#{type}")
    end

    def self.excluding_mimetype(type)
      new("!mimetype:#{type}")
    end

    def self.by_digest(digest)
      new("digest:#{digest}")
    end

    def self.by_url(pattern)
      new("original:#{pattern}")
    end

    def self.by_urlkey(pattern)
      new("urlkey:#{pattern}")
    end

    def and(other)
      [self, other]
    end

    def self.combine(*filters)
      filters.flatten
    end

    def self.only_successful
      [by_status(200)]
    end

    def self.excluding_errors
      [excluding_status(404), excluding_status(500),
       excluding_status(502), excluding_status(503)]
    end

    private

    def validate!
      if @expression.empty?
        raise ArgumentError,
              "CDX filter expression cannot be empty"
      end

      field_name = field
      return if VALID_FIELDS.include?(field_name)

      raise ArgumentError,
            "Invalid CDX filter field: #{field_name}. " \
            "Valid fields: #{VALID_FIELDS.join(', ')}"
    end
  end
end
