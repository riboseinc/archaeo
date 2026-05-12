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

    def css?
      @content_type&.include?("text/css")
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

    def links
      return [] unless html?

      @links ||= begin
        doc = Nokogiri::HTML(@raw_content)
        base = @archive_url || @original_url
        doc.css("a[href]").map do |anchor|
          href = resolve_page_url(anchor["href"], base)
          { href: href, text: anchor.text.strip,
            external: href && !href.include?(original_domain) }
        end
      end
    end

    def meta_tags
      return {} unless html?

      @meta_tags ||= begin
        doc = Nokogiri::HTML(@raw_content)
        result = extract_meta_entries(doc)
        canonical = doc.at_css('link[rel="canonical"]')
        result["canonical"] = canonical["href"].to_s if canonical
        result
      end
    end

    def to_h
      {
        content_type: @content_type,
        status_code: @status_code,
        archive_url: @archive_url,
        original_url: @original_url,
        timestamp: @timestamp,
        size: size,
        encoding: encoding.to_s,
      }
    end

    def as_json(*)
      {
        content_type: @content_type,
        status_code: @status_code,
        archive_url: @archive_url,
        original_url: @original_url,
        timestamp: @timestamp.to_s,
        size: size,
        encoding: encoding.to_s,
      }
    end

    def inspect
      "#<#{self.class.name} #{@content_type} #{size} bytes>"
    end

    private

    def detect_encoding
      charset = extract_charset(@content_type)
      return Encoding.find(charset) if charset

      html_charset = detect_html_charset
      return Encoding.find(html_charset) if html_charset

      EncodingDetector.new.detect(@raw_content)
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

    def original_domain
      @original_domain ||= begin
        URI.parse(@original_url).host
      rescue URI::InvalidURIError
        nil
      end
    end

    def extract_meta_entries(doc)
      result = {}
      doc.css("meta[name], meta[property], meta[http-equiv]").each do |meta|
        key = meta["name"] || meta["property"] || meta["http-equiv"]
        next unless key

        result[key.downcase] = meta["content"].to_s
      end
      result
    end

    def resolve_page_url(href, base)
      return href unless href
      return href if href.start_with?("http", "//", "data:", "#",
                                      "javascript:")
      return nil unless base

      URI.join(base, href).to_s
    rescue URI::InvalidURIError
      nil
    end
  end
end
