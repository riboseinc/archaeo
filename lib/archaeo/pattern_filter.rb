# frozen_string_literal: true

module Archaeo
  # URL pattern filter for include/exclude matching during downloads.
  #
  # Supports string substring matching, Regexp objects, and
  # %r{...} and /.../ string-to-regexp conversion with inline flags.
  class PatternFilter
    def initialize(only: nil, exclude: nil)
      @only_patterns = compile_patterns(Array(only))
      @exclude_patterns = compile_patterns(Array(exclude))
    end

    def match?(url)
      url = url.to_s
      return false if excluded?(url)
      return true if @only_patterns.empty?

      included?(url)
    end

    def reject?(url)
      !match?(url)
    end

    def self.to_regex(pattern)
      case pattern
      when Regexp then pattern
      when String then parse_regex_string(pattern)
      else
        raise ArgumentError,
              "Pattern must be String or Regexp, got #{pattern.class}"
      end
    end

    private

    def compile_patterns(patterns)
      patterns.map { |p| self.class.to_regex(p) }
    end

    def included?(url)
      @only_patterns.any? { |re| url.match?(re) }
    end

    def excluded?(url)
      @exclude_patterns.any? { |re| url.match?(re) }
    end

    private_class_method def self.parse_regex_string(str)
      stripped = str.strip
      if stripped.start_with?("%r{") && stripped.end_with?("}")
        body = stripped[3..-2]
        build_regex(body)
      elsif stripped.start_with?("/") && stripped.end_with?("/")
        body = stripped[1..-2]
        build_regex(body)
      elsif stripped.start_with?("/") && stripped.length > 1
        last_slash = stripped.rindex("/")
        body = stripped[1...last_slash]
        flags = stripped[(last_slash + 1)..]
        build_regex(body, parse_flags(flags))
      else
        Regexp.new(Regexp.escape(stripped))
      end
    end

    private_class_method def self.build_regex(body, options = 0)
      Regexp.new(body, options)
    end

    private_class_method def self.parse_flags(flags)
      options = 0
      options |= Regexp::IGNORECASE if flags.include?("i")
      options |= Regexp::MULTILINE if flags.include?("m")
      options |= Regexp::EXTENDED if flags.include?("x")
      options
    end
  end
end
