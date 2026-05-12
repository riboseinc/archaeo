# frozen_string_literal: true

require "nokogiri"

module Archaeo
  # Rewrites Wayback Machine archive URLs to local file paths.
  #
  # Used for saving archived pages and their assets for offline
  # browsing. Converts absolute archive URLs into relative paths
  # rooted at a configurable local directory.
  #
  # Supports HTML attributes, srcset, inline styles, CSS url(),
  # JavaScript string URLs, and server-side extension handling.
  class UrlRewriter
    URL_ATTRS = %w[src href data-src data-url poster action].freeze
    CSS_URL_RE = /url\(\s*['"]?([^'")\s]+)['"]?\s*\)/
    ARCHIVE_RE = %r{https?://web\.archive\.org/web/\d+(?:id_)?/}
    JS_URL_RE = /['"](https?:\/\/web\.archive\.org\/web\/\d+(?:id_)?\/[^'"]+)['"]/

    SERVER_EXTENSIONS = %w[.php .asp .aspx .jsp .cgi .pl .py].freeze

    def initialize(archive_prefix, local_prefix,
                   rewrite_js: false, rewrite_absolute: false,
                   server_extensions: false)
      @archive_prefix = archive_prefix.to_s
      @local_prefix = local_prefix.to_s
      @rewrite_js = rewrite_js
      @rewrite_absolute = rewrite_absolute
      @server_extensions = server_extensions
    end

    def rewrite(url)
      if @rewrite_absolute && url.match?(ARCHIVE_RE)
        return rewrite_absolute_url(url)
      end

      return url unless url.start_with?(@archive_prefix)

      relative = url.sub(@archive_prefix, "")
      File.join(@local_prefix, relative)
    end

    def rewrite_batch(urls)
      urls.map { |url| rewrite(url) }
    end

    def rewrite_html(html_content)
      doc = Nokogiri::HTML(html_content)
      rewrite_url_attrs(doc)
      rewrite_srcset_attrs(doc)
      rewrite_inline_style_attrs(doc)
      rewrite_style_elements(doc)
      doc.to_html
    end

    def rewrite_js(js_content)
      return js_content unless @rewrite_js

      js_content.gsub(JS_URL_RE) do
        quote = Regexp.last_match[0][0]
        url = Regexp.last_match[1]
        rewritten = rewrite(url)
        "#{quote}#{rewritten}#{quote}"
      end
    end

    def rewrite_css(css_content)
      css_content.gsub(CSS_URL_RE) do
        url = Regexp.last_match[1]
        if url.match?(ARCHIVE_RE) || url.start_with?(@archive_prefix)
          "url('#{rewrite(url)}')"
        else
          Regexp.last_match[0]
        end
      end
    end

    def rewrite_url_attrs(doc)
      URL_ATTRS.each do |attr|
        doc.css("[#{attr}]").each do |el|
          original = el[attr]
          next unless original

          if @rewrite_absolute && original.match?(ARCHIVE_RE)
            el[attr] = rewrite_absolute_url(original)
          elsif original.start_with?(@archive_prefix)
            el[attr] = rewrite(original)
          end
        end
      end
    end

    def rewrite_srcset_attrs(doc)
      doc.css("[srcset]").each do |el|
        el["srcset"] = rewrite_srcset(el["srcset"])
      end
    end

    private

    def rewrite_inline_style_attrs(doc)
      doc.css("[style]").each do |el|
        next unless el["style"]

        el["style"] = rewrite_css_urls(el["style"])
      end
    end

    def rewrite_style_elements(doc)
      doc.css("style").each do |el|
        el.content = rewrite_css_urls(el.text)
      end
    end

    def rewrite_css_urls(css_text)
      css_text.gsub(CSS_URL_RE) do
        url = Regexp.last_match[1]
        if url.match?(ARCHIVE_RE) || url.start_with?(@archive_prefix)
          "url('#{rewrite(url)}')"
        else
          Regexp.last_match[0]
        end
      end
    end

    def rewrite_srcset(srcset)
      return srcset unless srcset

      srcset.split(",").map do |entry|
        parts = entry.strip.split(/\s+/, 2)
        url = parts[0]
        descriptor = parts[1]

        rewritten = if @rewrite_absolute && url.match?(ARCHIVE_RE)
                      rewrite_absolute_url(url)
                    elsif url.start_with?(@archive_prefix)
                      rewrite(url)
                    else
                      url
                    end
        descriptor ? "#{rewritten} #{descriptor}" : rewritten
      end.join(", ")
    end

    def rewrite_absolute_url(url)
      rest = url.sub(ARCHIVE_RE, "")
      File.join(@local_prefix, rest)
    end
  end
end
