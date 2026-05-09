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
    end

    def extract_images(list)
      @doc.css("img[src]").each do |el|
        list.add(resolve(el["src"]), type: :image)
      end
    end

    def extract_fonts(list)
      @doc.css('link[rel="preload"][as="font"]').each do |el|
        list.add(resolve(el["href"]), type: :font)
      end
      @doc.css('link[rel="stylesheet"]').each do |el|
        if font_stylesheet?(el["href"])
          list.add(resolve(el["href"]),
                   type: :font)
        end
      end
    end

    def extract_media(list)
      @doc.css("source[src], video[src], audio[src]").each do |el|
        list.add(resolve(el["src"]), type: :media)
      end
    end

    def extract_inline_css(list)
      @doc.css("style").each do |el|
        extract_css_urls(el.text).each do |url|
          list.add(resolve(url), type: :font)
        end
      end
    end

    def font_stylesheet?(href)
      href.to_s.include?("fonts.googleapis.com") ||
        href.to_s.include?("font")
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
  end
end
