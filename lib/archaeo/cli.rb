# frozen_string_literal: true

require "csv"
require "json"
require "set"
require "thor"

module Archaeo
  # Command-line interface powered by Thor.
  class Cli < Thor
    map %w[--version -v] => :version

    class_option :quiet, type: :boolean, default: false,
                         desc: "Suppress progress messages"

    def self.exit_on_failure?
      true
    end

    desc "version", "Show archaeo version"
    def version
      puts "archaeo #{VERSION}"
    end

    desc "snapshots URL", "List archived snapshots for a URL"
    option :from, desc: "Start timestamp (YYYYMMDDHHmmss)"
    option :to, desc: "End timestamp (YYYYMMDDHHmmss)"
    option :match_type,
           desc: "Match type (exact, prefix, host, domain)"
    option :filter, type: :array, desc: "CDX filter expressions"
    option :filter_status, type: :array,
                           desc: "Only include these status codes"
    option :filter_type, type: :array,
                         desc: "MIME type prefixes (e.g. image, text/html)"
    option :collapse, type: :array, desc: "CDX collapse fields"
    option :sort, desc: "Sort order (default, closest, reverse)"
    option :limit, type: :numeric, desc: "Max snapshots to return"
    option :format, desc: "Output format (table, json, csv)",
                    default: "table"
    def snapshots(url)
      fmt = validate_output_format
      handle_errors do
        snaps = fetch_snapshots(url)
        output_formatted(snaps, fmt)
      end
    end

    desc "near URL TIMESTAMP",
         "Find the snapshot closest to a timestamp"
    option :format, desc: "Output format (url, json)", default: "url"
    def near(url, timestamp)
      handle_errors do
        snap = CdxApi.new.near(url, timestamp: timestamp)
        output_snapshot(snap)
      end
    end

    desc "oldest URL", "Find the oldest snapshot of a URL"
    option :format, desc: "Output format (url, json)", default: "url"
    def oldest(url)
      handle_errors do
        snap = CdxApi.new.oldest(url)
        output_snapshot(snap)
      end
    end

    desc "newest URL", "Find the newest snapshot of a URL"
    option :format, desc: "Output format (url, json)", default: "url"
    def newest(url)
      handle_errors do
        snap = CdxApi.new.newest(url)
        output_snapshot(snap)
      end
    end

    desc "before URL TIMESTAMP",
         "Find the nearest snapshot before a timestamp"
    option :format, desc: "Output format (url, json)", default: "url"
    def before(url, timestamp)
      handle_errors do
        snap = CdxApi.new.before(url, timestamp: timestamp)
        output_snapshot(snap)
      end
    end

    desc "after URL TIMESTAMP",
         "Find the nearest snapshot after a timestamp"
    option :format, desc: "Output format (url, json)", default: "url"
    def after(url, timestamp)
      handle_errors do
        snap = CdxApi.new.after(url, timestamp: timestamp)
        output_snapshot(snap)
      end
    end

    desc "between URL FROM TO",
         "List snapshots in a date range"
    option :format, desc: "Output format (table, json, csv)",
                    default: "table"
    def between(url, from, to)
      fmt = validate_output_format
      handle_errors do
        cdx = CdxApi.new
        snaps = cdx.between(url, from: from, to: to).to_a
        output_formatted(snaps, fmt)
      end
    end

    desc "available URL", "Check if a URL is archived"
    option :timestamp, desc: "Check near this timestamp (YYYYMMDDHHmmss)"
    def available(url)
      handle_errors do
        result = AvailabilityApi.new.near(
          url, timestamp: options[:timestamp]
        )
        if result.available?
          puts "Available: #{result.archive_url}"
        else
          puts "Not available"
          exit 1
        end
      end
    end

    desc "save URL", "Save a URL to the Wayback Machine"
    def save(url)
      handle_errors do
        result = SaveApi.new.save(url)
        label = result.cached? ? "Cached" : "Saved"
        puts "#{label}: #{result.archive_url}"
      end
    end

    desc "fetch URL TIMESTAMP",
         "Fetch archived content for a URL at a timestamp"
    option :identity, type: :boolean, default: false,
                      desc: "Fetch raw (identity) content"
    option :output, desc: "Write content to file"
    def fetch(url, timestamp)
      handle_errors do
        page = Fetcher.new.fetch(
          url, timestamp: timestamp,
               identity: options[:identity]
        )
        output_page(page)
      end
    end

    desc "fetch-assets URL TIMESTAMP",
         "Fetch a page and list its extracted assets"
    option :format, desc: "Output format (json, table)", default: "table"
    def fetch_assets(url, timestamp)
      handle_errors do
        bundle = Fetcher.new.fetch_page_with_assets(
          url, timestamp: timestamp
        )
        output_assets(bundle)
      end
    end

    desc "rewrite URL TIMESTAMP",
         "Fetch a page and rewrite archive URLs to local paths"
    option :prefix, desc: "Local path prefix", default: "local"
    option :output, desc: "Write rewritten HTML to file"
    def rewrite(url, timestamp)
      handle_errors do
        coerced = Timestamp.coerce(timestamp)
        page = Fetcher.new.fetch(url, timestamp: coerced)
        rewritten = build_rewriter(url, coerced).rewrite_html(page.content)
        output_rewritten(rewritten)
      end
    end

    desc "diff URL TIMESTAMP_A TIMESTAMP_B",
         "Compare assets of two archived snapshots"
    option :format, desc: "Output format (table, json)", default: "table"
    def diff(url, timestamp_a, timestamp_b)
      handle_errors do
        bundle_a = Fetcher.new.fetch_page_with_assets(
          url, timestamp: timestamp_a
        )
        bundle_b = Fetcher.new.fetch_page_with_assets(
          url, timestamp: timestamp_b
        )
        output_diff(bundle_a.assets, bundle_b.assets,
                    timestamp_a, timestamp_b)
      end
    end

    desc "asset-audit URL TIMESTAMP",
         "Audit assets for an archived page"
    option :format, desc: "Output format (table, json)", default: "table"
    def asset_audit(url, timestamp)
      handle_errors do
        bundle = Fetcher.new.fetch_page_with_assets(
          url, timestamp: timestamp
        )
        report = build_audit_report(bundle)
        case options[:format]
        when "json"
          puts JSON.generate(report)
        else
          print_audit_report(report)
        end
      end
    end

    desc "download URL", "Download all archived snapshots of a URL"
    option :output, desc: "Output directory", default: "archive"
    option :from, desc: "Start timestamp (YYYYMMDDHHmmss)"
    option :to, desc: "End timestamp (YYYYMMDDHHmmss)"
    option :resume, type: :boolean, default: false,
                    desc: "Resume interrupted download"
    option :concurrency, type: :numeric, default: 1,
                         desc: "Number of parallel downloads"
    option :dry_run, type: :boolean, default: false,
                     desc: "Preview downloads without fetching"
    def download(url)
      handle_errors do
        downloader = BulkDownloader.new(
          output_dir: options[:output],
          concurrency: options[:concurrency],
        )
        download_with_progress(downloader, url)
      end
    end

    desc "known_urls DOMAIN",
         "List all known URLs for a domain"
    def known_urls(domain)
      handle_errors do
        CdxApi.new.known_urls(domain).each do |u|
          puts u
        end
      end
    end

    desc "num_pages URL",
         "Show number of CDX result pages for a URL"
    def num_pages(url)
      handle_errors do
        puts CdxApi.new.num_pages(url)
      end
    end

    desc "count URL",
         "Count snapshots for a URL"
    def count(url)
      handle_errors do
        puts CdxApi.new.count(url)
      end
    end

    CDX_OPTION_MAP = {
      from: :from,
      to: :to,
      match_type: :match_type,
      filter: :filters,
      collapse: :collapse,
      sort: :sort,
      limit: :limit,
    }.freeze

    private

    def quiet?
      options[:quiet]
    end

    def handle_errors
      yield
    rescue RateLimitError => e
      warn "Rate limited: #{e.message}"
      exit 1
    rescue NoSnapshotFound => e
      warn "Not found: #{e.message}"
      exit 1
    rescue BlockedSiteError => e
      warn "Blocked: #{e.message}"
      exit 1
    rescue Error => e
      warn "Error: #{e.message}"
      exit 1
    end

    def validate_output_format
      fmt = options[:format].to_s
      fmt = "table" if fmt.empty?
      unless %w[table json csv].include?(fmt)
        warn "Unknown format '#{fmt}'. Use: table, json, csv"
        exit 1
      end
      fmt
    end

    def fetch_snapshots(url)
      cdx = CdxApi.new
      opts = build_cdx_options(options)
      cdx.snapshots(url, **opts).to_a
    end

    def output_formatted(snaps, fmt)
      case fmt
      when "json" then output_json(snaps)
      when "csv" then output_csv(snaps)
      else output_table(snaps)
      end
    end

    def output_snapshot(snap)
      case options[:format]
      when "json"
        puts JSON.generate(snap.as_json)
      else
        puts snap.archive_url
      end
    end

    def output_page(page)
      if options[:output]
        write_output(options[:output], page.content)
      elsif page.text? || page.json?
        $stdout.write(page.content)
      else
        warn "Binary content (#{page.content_type}). " \
             "Use --output FILE to save."
        exit 1
      end
    end

    def build_rewriter(url, timestamp)
      normalized = UrlNormalizer.normalize(url)
      archive_prefix = ArchiveUrl.new(normalized, timestamp: timestamp).to_s
      UrlRewriter.new(archive_prefix, options[:prefix])
    end

    def output_rewritten(content)
      if options[:output]
        write_output(options[:output], content)
      else
        $stdout.write(content)
      end
    end

    def output_diff(assets_a, assets_b, ts_a, ts_b)
      comparison = compare_asset_lists(assets_a, assets_b)
      case options[:format]
      when "json"
        puts JSON.generate(comparison)
      else
        print_diff_report(comparison, ts_a, ts_b)
      end
    end

    def output_assets(bundle)
      case options[:format]
      when "json"
        puts bundle.assets.to_json
      else
        bundle.assets.to_h.each do |type, urls|
          next if urls.empty?

          puts "#{type}:"
          urls.each { |url| puts "  #{url}" }
        end
      end
    end

    def download_with_progress(downloader, url)
      summary = downloader.download(
        url, from: options[:from], to: options[:to],
             resume: options[:resume], dry_run: options[:dry_run]
      ) { |c, t, s| print_progress(c, t, s) }
      print_summary(summary)
    end

    def print_progress(current, total, snap)
      return if quiet?

      warn "[#{current}/#{total}] #{snap.timestamp} #{snap.original_url}"
    end

    def print_summary(summary)
      return if quiet?

      parts = ["Downloaded #{summary.downloaded}/#{summary.total}"]
      parts << "#{summary.failed} failed" if summary.failed.positive?
      parts << "(#{summary.bytes_written} bytes)"
      parts << "in #{summary.elapsed.round(1)}s"
      warn parts.join(" ")
    end

    def build_cdx_options(opts)
      result = {}
      CDX_OPTION_MAP.each do |cli_key, api_key|
        value = opts[cli_key]
        result[api_key] = value if value
      end
      append_convenience_filters!(result, opts)
      result
    end

    def append_convenience_filters!(result, opts)
      filters = Array(result[:filters])
      filters += status_filters(opts[:filter_status])
      filters += type_filters(opts[:filter_type])
      result[:filters] = filters unless filters.empty?
    end

    def status_filters(codes)
      Array(codes).map { |code| CdxFilter.by_status(code).to_s }
    end

    def type_filters(prefixes)
      Array(prefixes).map { |p| CdxFilter.by_mimetype_prefix(p).to_s }
    end

    def output_table(snaps)
      snaps.each do |snap|
        puts "#{snap.timestamp}  #{snap.status_code}  " \
             "#{snap.original_url}"
      end
    end

    def output_json(snaps)
      data = snaps.map(&:as_json)
      puts JSON.generate(data)
    end

    def output_csv(snaps)
      csv = CSV.generate do |csv|
        csv << %w[timestamp status_code url archive_url]
        snaps.each do |snap|
          csv << [snap.timestamp.to_s, snap.status_code,
                  snap.original_url, snap.archive_url]
        end
      end
      puts csv
    end

    def write_output(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
      warn "Written to #{path}" unless quiet?
    end

    def compare_asset_lists(assets_a, assets_b)
      all_a = assets_a.all.to_set
      all_b = assets_b.all.to_set
      build_diff(all_a, all_b, assets_a.counts, assets_b.counts)
    end

    def build_diff(set_a, set_b, counts_a, counts_b)
      {
        only_in_a: (set_a - set_b).to_a.sort,
        only_in_b: (set_b - set_a).to_a.sort,
        unchanged: (set_a & set_b).to_a.sort,
        counts_a: counts_a,
        counts_b: counts_b,
      }
    end

    def print_diff_report(comparison, ts_a, ts_b)
      puts "Comparing #{ts_a} vs #{ts_b}"
      puts
      print_url_list("Removed:", comparison[:only_in_a], "  - ")
      print_url_list("Added:", comparison[:only_in_b], "  + ")
      puts "Unchanged: #{comparison[:unchanged].size}"
    end

    def print_url_list(header, urls, prefix)
      return unless urls.any?

      puts header
      urls.each { |url| puts "#{prefix}#{url}" }
      puts
    end

    def build_audit_report(bundle)
      assets = bundle.assets
      downloadable = assets.downloadable
      {
        page_url: bundle.page.archive_url,
        total_assets: assets.size,
        downloadable: downloadable.size,
        counts: assets.counts,
        domains: assets.domain_counts,
        duplicates: find_duplicate_urls(assets),
      }
    end

    def print_audit_report(report)
      puts "Page: #{report[:page_url]}"
      puts "Total assets: #{report[:total_assets]}"
      puts "Downloadable: #{report[:downloadable]}"
      puts
      print_type_counts(report[:counts])
      print_domain_counts(report[:domains])
      print_url_list("Duplicates:", report[:duplicates], "  ")
    end

    def print_type_counts(counts)
      puts "By type:"
      counts.each { |type, count| puts "  #{type}: #{count}" }
      puts
    end

    def print_domain_counts(domains)
      puts "By domain:"
      domains.sort_by { |_, v| -v }.each do |domain, count|
        puts "  #{domain}: #{count}"
      end
    end

    def find_duplicate_urls(assets)
      seen = {}
      dupes = []
      assets.all.each do |url|
        if seen[url]
          dupes << url unless dupes.include?(url)
        else
          seen[url] = true
        end
      end
      dupes
    end
  end
end
