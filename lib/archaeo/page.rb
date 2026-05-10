# frozen_string_literal: true

require "nokogiri"

module Archaeo
  # Model representing a fetched archived page from the Wayback Machine.
  #
  # Contains the page content, metadata, and provenance information
  # for a single archived resource. Content is automatically transcoded
  # to UTF-8 from the detected source encoding.
  class Page
    attr_reader :content_type, :status_code,
                :archive_url, :original_url, :timestamp

    def initialize(content:, content_type:, status_code:,
                   archive_url:, original_url:, timestamp:)
      @raw_content = content
      @content_type = content_type
      @status_code = status_code
      @archive_url = archive_url
      @original_url = original_url
      @timestamp = Timestamp.coerce(timestamp)
    end

    def content
      @content ||= transcode(@raw_content)
    end

    def size
      content.length
    end

    def encoding
      @encoding ||= detect_encoding
    end

    def html?
      @content_type&.include?("text/html")
    end

    def json?
      @content_type&.include?("application/json")
    end

    def image?
      @content_type&.start_with?("image/")
    end

    def text?
      @content_type&.start_with?("text/")
    end

    def binary?
      !(text? || json? || html?)
    end

    def title
      @title ||= begin
        doc = Nokogiri::HTML(@raw_content)
        doc.at_css("title")&.text&.strip
      rescue StandardError
        nil
      end
    end

    private

    def detect_encoding
      charset = extract_charset(@content_type)
      return Encoding.find(charset) if charset

      html_charset = detect_html_charset
      return Encoding.find(html_charset) if html_charset

      Encoding::UTF_8
    rescue ArgumentError
      Encoding::UTF_8
    end

    def extract_charset(content_type)
      return nil unless content_type

      match = content_type.match(/charset=([^\s;]+)/i)
      match ? match[1] : nil
    end

    def detect_html_charset
      doc = Nokogiri::HTML(@raw_content)
      node = doc.at_css("meta[charset]")
      return node["charset"] if node

      content = doc.at_css('meta[http-equiv="Content-Type"]')&.[]("content")
      return nil unless content

      match = content.match(/charset=([^\s;]+)/i)
      match ? match[1] : nil
    rescue StandardError
      nil
    end

    def transcode(raw)
      return raw if raw.encoding == Encoding::UTF_8 && raw.valid_encoding?
      return raw if raw.empty?

      encode_to_utf8(raw, encoding)
    rescue Encoding::InvalidByteSequenceError,
           Encoding::UndefinedConversionError
      encode_to_utf8(raw, Encoding::UTF_8)
    end

    def encode_to_utf8(raw, source_encoding)
      raw.force_encoding(source_encoding)
        .encode("UTF-8",
                invalid: :replace, undef: :replace,
                replace: "?")
    end
  end
end
