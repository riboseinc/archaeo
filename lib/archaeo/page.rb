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
      @title ||= html_doc.at_css("title")&.text&.strip
    end

    def links
      return [] unless html?

      @links ||= begin
        base = @archive_url || @original_url
        html_doc.css("a[href]").map do |anchor|
          href = resolve_page_url(anchor["href"], base)
          { href: href, text: anchor.text.strip,
            external: href && !href.include?(original_domain) }
        end
      end
    end

    def meta_tags
      return {} unless html?

      @meta_tags ||= begin
        result = extract_meta_entries(html_doc)
        canonical = html_doc.at_css('link[rel="canonical"]')
        result["canonical"] = canonical["href"].to_s if canonical
        result
      end
    end

    def headings
      return [] unless html?

      @headings ||= html_doc.css("h1, h2, h3, h4, h5, h6").map do |el|
        { level: el.name[1].to_i, text: el.text.strip }
      end
    end

    def images
      return [] unless html?

      @images ||= html_doc.css("img[src]").map do |el|
        { src: el["src"], alt: el["alt"].to_s,
          width: el["width"]&.to_i, height: el["height"]&.to_i }
      end
    end

    def forms
      return [] unless html?

      @forms ||= html_doc.css("form").map do |form|
        { action: form["action"].to_s, method: (form["method"] || "GET").upcase,
          fields: extract_form_fields(form) }
      end
    end

    def scripts
      return [] unless html?

      @scripts ||= html_doc.css("script").map do |el|
        { src: el["src"].to_s, type: el["type"].to_s }
      end
    end

    def microposts
      return [] unless html?

      @microposts ||= begin
        containers = find_article_containers(html_doc)
        containers.filter_map { |el| extract_micropost(el) }
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
      to_h.transform_values { |v| v.is_a?(Timestamp) ? v.to_s : v }
    end

    def inspect
      "#<#{self.class.name} #{@content_type} #{size} bytes>"
    end

    private

    def html_doc
      @html_doc ||= Nokogiri::HTML(@raw_content)
    end

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
      node = html_doc.at_css("meta[charset]")
      return node["charset"] if node

      content = html_doc.at_css('meta[http-equiv="Content-Type"]')&.[]("content")
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
      return href if href.start_with?("http:", "https:", "//", "data:",
                                      "#", "javascript:")
      return nil unless base

      URI.join(base, href).to_s
    rescue URI::InvalidURIError
      nil
    end

    def extract_form_fields(form)
      inputs = form.css("input, select, textarea").map do |el|
        { name: el["name"].to_s, type: (el["type"] || el.name).to_s }
      end
      inputs.reject { |f| f[:name].empty? }
    end

    ARTICLE_SELECTORS = %w[
      article [role=article] .post .entry .blog-post
      .hentry .post-content .entry-content .article-content
      .story .story-body .news-article
    ].freeze

    def find_article_containers(doc)
      found = ARTICLE_SELECTORS
        .filter_map { |sel| doc.css(sel) }
        .flat_map(&:to_a)
      found.any? ? found.uniq : [doc.at_css("body") || doc]
    end

    def extract_micropost(element)
      title = extract_micropost_title(element)
      body = extract_micropost_body(element)
      return nil if body.nil? || body.strip.empty?

      { title: title, body: body.strip,
        date: extract_micropost_date(element),
        author: extract_micropost_author(element) }
    end

    def extract_micropost_title(el)
      heading = el.at_css("h1, h2, h3, [class*=title], [class*=heading]")
      heading&.text&.strip
    end

    def extract_micropost_body(el)
      paragraphs = el.css("p").map(&:text).join("\n")
      return nil if paragraphs.strip.empty?

      paragraphs
    end

    def extract_micropost_date(el)
      time = el.at_css("time[datetime]")
      return time["datetime"] if time

      date_el = el.at_css(
        "[class*=date], [class*=time], [class*=published], " \
        "[property='datePublished']",
      )
      date_el&.text&.strip
    end

    def extract_micropost_author(el)
      author_el = el.at_css(
        "[class*=author], [rel=author], [property='author']",
      )
      author_el&.text&.strip
    end
  end
end
