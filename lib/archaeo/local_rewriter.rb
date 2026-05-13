# frozen_string_literal: true

require "fileutils"

module Archaeo
  LocalRewriteSummary = Struct.new(
    :total, :rewritten, :skipped, :elapsed,
    keyword_init: true
  )

  # Rewrites previously downloaded files by converting archive URLs
  # to local paths. Operates on files already on disk without fetching.
  class LocalRewriter
    def initialize(prefix: "local", rewrite_js: false,
                   rewrite_absolute: false)
      @prefix = prefix
      @rewrite_js = rewrite_js
      @rewrite_absolute = rewrite_absolute
    end

    def rewrite_directory(input_dir, output_dir)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      files = gather_files(input_dir)
      rewritten = 0
      skipped = 0

      files.each do |path|
        rel = path.sub(%r{\A#{Regexp.escape(input_dir)}/?}, "")
        out_path = File.join(output_dir, rel)

        result = rewrite_file(path, out_path)
        result ? rewritten += 1 : skipped += 1
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      LocalRewriteSummary.new(
        total: files.size, rewritten: rewritten,
        skipped: skipped, elapsed: elapsed
      )
    end

    def rewrite_file(input_path, output_path)
      content = File.read(input_path)
      return nil unless rewrite_candidate?(content)

      FileUtils.mkdir_p(File.dirname(output_path))
      rewriter = build_rewriter
      rewritten = apply_rewriting(rewriter, content, input_path)
      File.write(output_path, rewritten)
      true
    end

    private

    def gather_files(dir)
      Dir.glob(File.join(dir, "**", "*"))
        .select { |f| File.file?(f) && text_file?(f) }
    end

    def text_file?(path)
      ext = File.extname(path).downcase
      TEXT_EXTENSIONS.include?(ext)
    end

    TEXT_EXTENSIONS = %w[
      .html .htm .xhtml .css .js .json .xml .txt
      .svg .md .yaml .yml .rss .atom
    ].freeze

    def rewrite_candidate?(content)
      content.include?("web.archive.org")
    end

    def build_rewriter
      UrlRewriter.new(
        "https://web.archive.org", @prefix,
        rewrite_js: @rewrite_js,
        rewrite_absolute: @rewrite_absolute
      )
    end

    def apply_rewriting(rewriter, content, path)
      ext = File.extname(path).downcase
      case ext
      when ".html", ".htm", ".xhtml"
        rewriter.rewrite_html(content)
      when ".css"
        rewriter.rewrite_css(content)
      when ".js"
        rewriter.rewrite_js(content)
      else
        rewrite_mixed(rewriter, content)
      end
    end

    def rewrite_mixed(rewriter, content)
      if content.include?("<") && content.include?(">")
        rewriter.rewrite_html(content)
      elsif content.include?("url(")
        rewriter.rewrite_css(content)
      else
        rewriter.rewrite_js(content)
      end
    end
  end
end
