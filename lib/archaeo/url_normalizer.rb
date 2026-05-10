# frozen_string_literal: true

module Archaeo
  # Sanitizes and normalizes URLs for Wayback Machine API queries.
  #
  # Handles common URL issues: whitespace, surrounding quotes,
  # double percent-encoding, and inconsistent percent-encoding case.
  class UrlNormalizer
    attr_reader :original, :normalized

    def initialize(url)
      @original = url.to_s
      @normalized = normalize(@original)
    end

    def self.normalize(url)
      new(url).normalized
    end

    def self.with_scheme(url)
      normalized = normalize(url)
      normalized.match?(%r{\A[a-z][a-z0-9+\-.]*://}) ? normalized : "https://#{normalized}"
    end

    VALID_URL_RE = %r{\A([a-z][a-z0-9+\-.]*://)?[^\s]+\z}

    def self.valid?(url)
      normalized = normalize(url)
      return false if normalized.empty?

      normalized.match?(VALID_URL_RE)
    end

    def self.validate!(url)
      normalized = normalize(url)
      raise ArgumentError, "URL cannot be empty" if normalized.empty?
      raise ArgumentError, "Invalid URL: #{url}" unless valid?(url)

      normalized
    end

    def to_s
      @normalized
    end

    private

    def normalize(url)
      url = strip_whitespace(url)
      url = strip_surrounding_quotes(url)
      url = fix_double_percent_encoding(url)
      url = normalize_percent_encoding(url)
      remove_default_port(url)
    end

    def strip_whitespace(url)
      url.strip
    end

    def strip_surrounding_quotes(url)
      url = url[1..-2] if url.start_with?('"') && url.end_with?('"')
      url = url[1..-2] if url.start_with?("'") && url.end_with?("'")
      url
    end

    def fix_double_percent_encoding(url)
      url.gsub(/%25([0-9A-Fa-f]{2})/i, '%\1')
    end

    def normalize_percent_encoding(url)
      url.gsub(/%[0-9a-f]{2}/i, &:upcase)
    end

    def remove_default_port(url)
      url.sub(%r{(https://[^/:]+):443(?=/|$)}, '\1')
        .sub(%r{(http://[^/:]+):80(?=/|$)}, '\1')
    end
  end
end
