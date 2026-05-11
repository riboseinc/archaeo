# frozen_string_literal: true

require "nokogiri"
require "uri"

module Archaeo
  # Extracts resource URLs from archived HTML content using Nokogiri.
  #
  # Parses the HTML DOM to find CSS, JavaScript, images, fonts,
  # and media resources referenced by the page. Optionally resolves
  # relative URLs against a base URL.
  class AssetExtractor
    FONT_CDN_PATTERNS = %w[
      fonts.googleapis.com
      fonts.gstatic.com
      use.typekit.net
      fast.fonts.net
      cloud.typography.com
    ].freeze

    CSS_URL_PATTERN = /url\(\s*['"]?([^'")\s]+)['"]?\s*\)/
    CSS_IMAGE_PROPS = Regexp.new(
      "(?:background-image|background|list-style-image|content|cursor)" \
      "\\s*:[^;]*#{CSS_URL_PATTERN.source}",
    )

    PRELOAD_TYPE_MAP = {
      "style" => :css,
      "script" => :js,
      "image" => :image,
    }.freeze

    def initialize(html, base_url: nil)
      @doc = Nokogiri::HTML(html.to_s)
      @base_url = base_url
    end

    def extract
      list = AssetList.new
      extract_css(list)
      extract_js(list)
      extract_images(list)
      extract_fonts(list)
      extract_media(list)
      extract_inline_css(list)
      extract_inline_styles(list)
      extract_preloads(list)
      list
    end

    private

    def extract_css(list)
      @doc.css('link[rel="stylesheet"]').each do |el|
        list.add(resolve(el["href"]), type: :css)
      end
    end

    def extract_js(list)
      @doc.css("script[src]").each do |el|
        list.add(resolve(el["src"]), type: :js)
      end
      @doc.css('link[rel="modulepreload"]').each do |el|
        list.add(resolve(el["href"]), type: :js)
      end
    end

    def extract_images(list)
      extract_img_tags(list)
      extract_picture_sources(list)
      extract_lazy_images(list)
      extract_icon_links(list)
    end

    def extract_img_tags(list)
      @doc.css("img[src]").each do |el|
        list.add(resolve(el["src"]), type: :image)
        extract_srcset(el["srcset"], list, :image)
      end
    end

    def extract_picture_sources(list)
      @doc.css("picture source[srcset]").each do |el|
        extract_srcset(el["srcset"], list, :image)
      end
    end

    def extract_lazy_images(list)
      @doc.css("img[data-src]").each do |el|
        list.add(resolve(el["data-src"]), type: :image)
      end
    end

    def extract_icon_links(list)
      @doc.css(
        'link[rel~="icon"], link[rel="apple-touch-icon"], ' \
        'link[rel="apple-touch-icon-precomposed"], ' \
        'link[rel="mask-icon"]',
      ).each do |el|
        list.add(resolve(el["href"]), type: :image)
      end

      @doc.css('link[rel="manifest"]').each do |el|
        list.add(resolve(el["href"]), type: :media)
      end
    end

    def extract_fonts(list)
      @doc.css('link[rel="preload"][as="font"]').each do |el|
        list.add(resolve(el["href"]), type: :font)
      end
      @doc.css('link[rel="stylesheet"]').each do |el|
        if font_stylesheet?(el["href"])
          list.add(resolve(el["href"]), type: :font)
        end
      end
    end

    def extract_media(list)
      extract_media_sources(list)
      extract_video_posters(list)
      extract_embeds(list)
      extract_tracks(list)
    end

    def extract_media_sources(list)
      @doc.css("source[src], video[src], audio[src]").each do |el|
        list.add(resolve(el["src"]), type: :media)
      end
    end

    def extract_video_posters(list)
      @doc.css("video[poster]").each do |el|
        list.add(resolve(el["poster"]), type: :image)
      end
    end

    def extract_embeds(list)
      @doc.css("iframe[src], embed[src]").each do |el|
        list.add(resolve(el["src"]), type: :media)
      end
      @doc.css("object[data]").each do |el|
        list.add(resolve(el["data"]), type: :media)
      end
    end

    def extract_tracks(list)
      @doc.css("track[src]").each do |el|
        list.add(resolve(el["src"]), type: :media)
      end
    end

    def extract_inline_css(list)
      @doc.css("style").each do |el|
        text = el.text
        extract_css_at_imports(text, list)
        extract_css_font_urls(text, list)
        extract_css_image_urls(text, list)
      end
    end

    def extract_inline_styles(list)
      @doc.css("[style]").each do |el|
        style = el["style"]
        next unless style

        style.scan(/url\(\s*['"]?([^'")\s]+)['"]?\s*\)/).flatten.each do |url|
          list.add(resolve(url), type: :image)
        end
      end
    end

    def extract_srcset(srcset_value, list, type)
      return if srcset_value.nil?

      srcset_value.split(",").each do |entry|
        url = entry.strip.split(/\s+/, 2).first
        list.add(resolve(url), type: type) if url && !url.empty?
      end
    end

    def extract_css_at_imports(text, list)
      text.scan(
        /@import\s+(?:url\(\s*['"]?([^'")\s]+)['"]?\s*\)|['"]([^'"]+)['"])/,
      ).flatten.compact.each do |url|
        next if url.nil? || url.empty?

        list.add(resolve(url), type: :css)
      end
    end

    def extract_css_font_urls(text, list)
      text.scan(/@font-face\s*\{[^}]*\}/m).each do |font_block|
        extract_css_urls(font_block).each do |url|
          list.add(resolve(url), type: :font)
        end
      end
    end

    def extract_css_image_urls(text, list)
      text.scan(CSS_IMAGE_PROPS).flatten.each do |url|
        list.add(resolve(url), type: :image)
      end
    end

    def font_stylesheet?(href)
      return false if href.nil?

      FONT_CDN_PATTERNS.any? { |pattern| href.include?(pattern) }
    end

    def extract_css_urls(css_text)
      css_text.scan(/url\(\s*['"]?([^'")\s]+)['"]?\s*\)/).flatten
    end

    def resolve(url)
      return url if url.nil? || url.empty?
      return url if url.start_with?("http", "//", "data:", "#")
      return url unless @base_url

      URI.join(@base_url, url).to_s
    rescue URI::InvalidURIError
      url
    end

    def extract_preloads(list)
      @doc.css('link[rel="preload"][as]').each do |el|
        type = PRELOAD_TYPE_MAP[el["as"]]
        next unless type

        list.add(resolve(el["href"]), type: type)
      end
    end
  end
end
