# frozen_string_literal: true

require "uri"

module Archaeo
  # Discovers subdomains from downloaded content.
  #
  # Scans HTML, CSS, and JavaScript files for links to subdomains
  # of a base domain, enabling recursive archival.
  class SubdomainDiscovery
    MULTI_PART_TLDS = %w[
      co.uk com.au co.jp co.nz co.za com.br com.mx
      com.sg co.in co.kr com.tw com.hk org.uk ac.uk
      co.il com.ar co.id co.th com.my com.tr co.ke
    ].freeze

    HTML_URL_ATTRS = %w[href src action].freeze
    HTML_URL_RE = /https?:\/\/([a-z0-9][-a-z0-9.]*[a-z0-9])/i
    CSS_URL_RE = /url\(\s*['"]?(https?:\/\/[^'")\s]+)['"]?\s*\)/i
    JS_STRING_RE = /['"](https?:\/\/[a-z0-9][-a-z0-9.]*[a-z0-9][^\s'"]*)['"]/i

    def initialize(base_domain, max_depth: 1)
      @base_domain = base_domain.to_s
      @max_depth = max_depth
      @visited = Set.new
    end

    def scan_content(content, content_type:)
      urls = extract_urls(content, content_type)
      filter_subdomains(urls)
    end

    def scan_files(directory)
      found = Set.new
      Dir.glob(File.join(directory, "**", "*")).each do |path|
        next unless File.file?(path)

        content = File.read(path, encoding: "UTF-8",
                                  invalid: :replace, undef: :replace)
        ext = File.extname(path).downcase
        content_type = content_type_for_ext(ext)
        next unless content_type

        found.merge(scan_content(content, content_type: content_type))
      end
      found.to_a
    end

    def discover_recursive(directory, depth: 0)
      return [] if depth >= @max_depth

      subdomains = scan_files(directory)
      new_subdomains = subdomains.reject { |s| @visited.include?(s) }
      @visited.merge(new_subdomains)
      new_subdomains
    end

    def base_domain(host)
      parts = host.to_s.downcase.split(".")
      return host.to_s if parts.length <= 2

      MULTI_PART_TLDS.each do |tld|
        tld_parts = tld.split(".")
        if parts.last(tld_parts.length) == tld_parts
          return parts.last(tld_parts.length + 1).join(".")
        end
      end

      parts.last(2).join(".")
    end

    private

    def extract_urls(content, content_type)
      case content_type
      when :html then extract_html_urls(content)
      when :css  then extract_css_urls(content)
      when :js   then extract_js_urls(content)
      else []
      end
    end

    def extract_html_urls(content)
      content.scan(HTML_URL_RE).flatten.map { |h| "https://#{h}" }
    end

    def extract_css_urls(content)
      content.scan(CSS_URL_RE).flatten
    end

    def extract_js_urls(content)
      content.scan(JS_STRING_RE).flatten
    end

    def filter_subdomains(urls)
      base = base_domain(@base_domain)
      urls.filter_map do |url|
        host = begin
          URI.parse(url).host.to_s.downcase
        rescue URI::InvalidURIError
          next
        end
        next unless host.end_with?(".#{base}") && host != base

        host
      end.uniq
    end

    def content_type_for_ext(ext)
      case ext
      when ".html", ".htm" then :html
      when ".css"          then :css
      when ".js"           then :js
      end
    end
  end
end
