# frozen_string_literal: true

require "nokogiri"

module Archaeo
  # Rewrites Wayback Machine archive URLs to local file paths.
  #
  # Used for saving archived pages and their assets for offline
  # browsing. Converts absolute archive URLs into relative paths
  # rooted at a configurable local directory.
  class UrlRewriter
    URL_ATTRS = %w[src href data-src poster].freeze
    CSS_URL_RE = /url\(\s*['"]?([^'")\s]+)['"]?\s*\)/

    def initialize(archive_prefix, local_prefix)
      @archive_prefix = archive_prefix.to_s
      @local_prefix = local_prefix.to_s
    end

    def rewrite(url)
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

    def rewrite_url_attrs(doc)
      URL_ATTRS.each do |attr|
        doc.css("[#{attr}]").each do |el|
          original = el[attr]
          next unless original&.start_with?(@archive_prefix)

          el[attr] = rewrite(original)
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
        rewritten = url.start_with?(@archive_prefix) ? rewrite(url) : url
        "url('#{rewritten}')"
      end
    end

    def rewrite_srcset(srcset)
      return srcset unless srcset

      srcset.split(",").map do |entry|
        parts = entry.strip.split(/\s+/, 2)
        url = parts[0]
        descriptor = parts[1]
        rewritten = url.start_with?(@archive_prefix) ? rewrite(url) : url
        descriptor ? "#{rewritten} #{descriptor}" : rewritten
      end.join(", ")
    end
  end
end
