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
    class_option :no_color, type: :boolean, default: false,
                            desc: "Disable colored output"

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
    option :exact_url, type: :boolean, default: false,
                       desc: "Match exact URL only"
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
    option :fields, type: :array,
                    desc: "Specific fields to print (timestamp,original,etc)"
    option :list_only, type: :boolean, default: false,
                       desc: "List files that would be downloaded"
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
    option :headers, type: :boolean, default: false,
                     desc: "Show response headers"
    def save(url)
      handle_errors do
        result = SaveApi.new.save(url)
        label = result.cached? ? "Cached" : "Saved"
        puts "#{label}: #{result.archive_url}"
        if options[:headers] && result.response_headers
          puts "Status: #{result.status_code}"
          puts "Response URL: #{result.response_url}" if result.response_url
          puts "Headers:"
          result.response_headers.each do |k, v|
            puts "  #{k}: #{v}"
          end
        end
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
    option :rewrite_js, type: :boolean, default: false,
                        desc: "Rewrite URLs in JavaScript strings"
    option :rewrite_absolute, type: :boolean, default: false,
                              desc: "Rewrite all absolute archive URLs"
    def rewrite(url, timestamp)
      handle_errors do
        coerced = Timestamp.coerce(timestamp)
        page = Fetcher.new.fetch(url, timestamp: coerced)
        rewriter = build_rewriter(url, coerced)
        rewritten = rewriter.rewrite_html(page.content)
        output_rewritten(rewritten)
      end
    end

    desc "rewrite-local INPUT_DIR",
         "Rewrite previously downloaded files to use local paths"
    option :output, desc: "Output directory (default: rewrite in-place)",
                    required: false
    option :prefix, desc: "Local path prefix", default: "local"
    option :rewrite_js, type: :boolean, default: false,
                        desc: "Rewrite URLs in JavaScript strings"
    option :rewrite_absolute, type: :boolean, default: false,
                              desc: "Rewrite all absolute archive URLs"
    def rewrite_local(input_dir)
      handle_errors do
        output_dir = options[:output] || input_dir
        local_rewriter = LocalRewriter.new(
          prefix: options[:prefix],
          rewrite_js: options[:rewrite_js],
          rewrite_absolute: options[:rewrite_absolute],
        )
        summary = local_rewriter.rewrite_directory(input_dir, output_dir)
        color = build_color
        warn color.success(
          "Rewrote #{summary.rewritten}/#{summary.total} files " \
          "in #{summary.elapsed.round(1)}s",
        )
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
    option :reset, type: :boolean, default: false,
                   desc: "Clear download state and cache for fresh start"
    option :concurrency, type: :numeric, default: 1,
                         desc: "Number of parallel downloads"
    option :dry_run, type: :boolean, default: false,
                     desc: "Preview downloads without fetching"
    option :all_timestamps, type: :boolean, default: false,
                            desc: "Download all timestamps, not just latest"
    option :only, desc: "Only download URLs matching this pattern"
    option :exclude, desc: "Exclude URLs matching this pattern"
    option :page_requisites, type: :boolean, default: false,
                             desc: "Download linked assets (CSS/JS/images)"
    option :snapshot_at, desc: "Download composite snapshot at timestamp"
    option :rate_limit, type: :numeric, default: 0,
                        desc: "Min seconds between requests"
    option :max_snapshots, type: :numeric,
                           desc: "Limit to N most recent snapshots"
    option :recursive_subdomains, type: :boolean, default: false,
                                  desc: "Discover and download subdomains"
    option :subdomain_depth, type: :numeric, default: 1,
                             desc: "Max subdomain recursion depth"
    option :strategy, desc: "Download strategy (newest_first, oldest_first, " \
                            "breadth_first, depth_first)",
                      default: "newest_first"
    def download(url)
      handle_errors do
        rate_limiter = RateLimiter.new(
          min_interval: options[:rate_limit].to_f,
        )
        filter = build_filter
        downloader = BulkDownloader.new(
          output_dir: options[:output],
          concurrency: options[:concurrency],
          rate_limiter: rate_limiter,
        )
        download_with_progress(downloader, url, filter)
      end
    end

    desc "health URL", "Check health of archived snapshots"
    option :from, desc: "Start timestamp"
    option :to, desc: "End timestamp"
    option :sample, type: :numeric, desc: "Check only N snapshots"
    option :format, desc: "Output format (table, json)", default: "table"
    def health(url)
      handle_errors do
        checker = ArchiveHealthCheck.new
        report = checker.check(
          url,
          from: options[:from],
          to: options[:to],
          sample: options[:sample],
        )
        output_health(report)
      end
    end

    desc "known_urls DOMAIN",
         "List all known URLs for a domain"
    option :subdomain, type: :boolean, default: false,
                       desc: "Include subdomain URLs"
    option :file, desc: "Save URLs to file"
    def known_urls(domain)
      handle_errors do
        match_type = options[:subdomain] ? "domain" : "prefix"
        urls = CdxApi.new.known_urls(domain, match_type: match_type)
        if options[:file]
          save_urls_to_file(urls, options[:file])
        else
          urls.each { |u| puts u }
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

    desc "coverage URL",
         "Analyze archive coverage for a URL"
    option :from, desc: "Start timestamp (YYYYMMDDHHmmss)"
    option :to, desc: "End timestamp (YYYYMMDDHHmmss)"
    option :format, desc: "Output format (table, json)", default: "table"
    def coverage(url)
      handle_errors do
        analyzer = CoverageAnalyzer.new
        report = analyzer.analyze(url, from: options[:from], to: options[:to])
        output_coverage(report)
      end
    end

    desc "snapshot-diff URL TIMESTAMP_A TIMESTAMP_B",
         "Compare two snapshots of a URL"
    option :format, desc: "Output format (table, json)", default: "table"
    def snapshot_diff(url, timestamp_a, timestamp_b)
      handle_errors do
        fetcher = Fetcher.new
        page_a = fetcher.fetch(url, timestamp: timestamp_a)
        page_b = fetcher.fetch(url, timestamp: timestamp_b)
        diff = SnapshotDiff.new(
          url: url, page_a: page_a, page_b: page_b,
          timestamp_a: timestamp_a, timestamp_b: timestamp_b
        )
        output_snapshot_diff(diff)
      end
    end

    desc "search URL QUERY", "Search archived snapshots for text"
    option :from, desc: "Start timestamp (YYYYMMDDHHmmss)"
    option :to, desc: "End timestamp (YYYYMMDDHHmmss)"
    option :max_results, type: :numeric, desc: "Maximum results to return"
    option :case_sensitive, type: :boolean, default: false,
                            desc: "Case-sensitive search"
    option :format, desc: "Output format (table, json)", default: "table"
    def search(url, query)
      handle_errors do
        searcher = ArchiveSearch.new
        results = searcher.search(
          url, query: query,
               from: options[:from], to: options[:to],
               max_results: options[:max_results],
               case_sensitive: options[:case_sensitive]
        )
        output_search_results(results)
      end
    end

    desc "track-changes URL",
         "Track content changes over time"
    option :from, desc: "Start timestamp (YYYYMMDDHHmmss)"
    option :to, desc: "End timestamp (YYYYMMDDHHmmss)"
    option :format, desc: "Output format (table, json)", default: "table"
    def track_changes(url)
      handle_errors do
        tracker = ContentTracker.new
        report = tracker.track(url, from: options[:from], to: options[:to])
        output_content_changes(report)
      end
    end

    desc "warc-export URL", "Export snapshots to WARC format"
    option :output, desc: "Output WARC file path", required: true
    option :from, desc: "Start timestamp (YYYYMMDDHHmmss)"
    option :to, desc: "End timestamp (YYYYMMDDHHmmss)"
    option :gzip, type: :boolean, default: false,
                  desc: "Write gzip-compressed WARC (.warc.gz)"
    def warc_export(url)
      handle_errors do
        fetcher = Fetcher.new
        cdx = CdxApi.new
        opts = {}
        opts[:from] = options[:from] if options[:from]
        opts[:to] = options[:to] if options[:to]
        snapshots = cdx.snapshots(url, **opts)
          .select(&:success?).to_a

        pages = snapshots.filter_map do |snap|
          fetcher.fetch(snap.original_url, timestamp: snap.timestamp)
        rescue Error
          nil
        end

        WarcWriter.new.write(options[:output], pages,
                             compress: options[:gzip])
        color = build_color
        warn color.success("Exported #{pages.size} snapshots to #{options[:output]}")
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
      warn build_color.warning("Rate limited: #{e.message}")
      exit 1
    rescue NoSnapshotFound => e
      warn build_color.error("Not found: #{e.message}")
      exit 1
    rescue BlockedSiteError => e
      warn build_color.error("Blocked: #{e.message}")
      exit 1
    rescue Error => e
      warn build_color.error("Error: #{e.message}")
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
      if options[:exact_url]
        opts[:match_type] = "exact"
      end
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
      UrlRewriter.new(
        archive_prefix, options[:prefix],
        rewrite_js: options[:rewrite_js],
        rewrite_absolute: options[:rewrite_absolute]
      )
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

    def build_filter
      only = options[:only]
      exclude = options[:exclude]
      return nil unless only || exclude

      PatternFilter.new(only: only, exclude: exclude)
    end

    def download_with_progress(downloader, url, filter)
      if options[:reset]
        state = DownloadState.new(options[:output])
        state.clear
      end

      summary = downloader.download(
        url,
        from: options[:from], to: options[:to],
        resume: options[:resume], dry_run: options[:dry_run],
        all_timestamps: options[:all_timestamps],
        filter: filter,
        page_requisites: options[:page_requisites],
        snapshot_at: options[:snapshot_at],
        max_snapshots: options[:max_snapshots],
        strategy: options[:strategy]&.to_sym
      ) { |c, t, s| print_progress(c, t, s) }
      print_summary(summary)

      return unless options[:recursive_subdomains]

      discover_and_download_subdomains(url, downloader, filter)
    end

    def discover_and_download_subdomains(url, downloader, filter)
      discovery = SubdomainDiscovery.new(
        URI.parse(UrlNormalizer.normalize(url)).host,
        max_depth: options[:subdomain_depth],
      )
      subdomains = discovery.scan_files(options[:output])
      subdomains.each do |subdomain|
        warn "Downloading subdomain: #{subdomain}" unless quiet?
        downloader.download(
          subdomain,
          from: options[:from], to: options[:to],
          resume: options[:resume],
          filter: filter
        ) { |c, t, s| print_progress(c, t, s) }
      end
    end

    def output_health(report)
      case options[:format]
      when "json"
        data = {
          total: report.total,
          accessible: report.accessible,
          missing: report.missing,
          errors: report.errors,
        }
        puts JSON.generate(data)
      else
        puts "Total: #{report.total}"
        puts "Accessible: #{report.accessible}"
        puts "Missing: #{report.missing}"
        puts "Errors: #{report.errors}"
      end
    end

    def save_urls_to_file(urls, file_path)
      FileUtils.mkdir_p(File.dirname(file_path)) unless File.dirname(file_path) == "."
      File.open(file_path, "w") do |f|
        urls.each do |url|
          f.puts(url)
        end
      end
      warn "Saved #{urls.size} URLs to #{file_path}" unless quiet?
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

    def output_coverage(report)
      case options[:format]
      when "json"
        puts JSON.generate(report.as_json)
      else
        puts "URL: #{report.url}"
        puts "Total URLs: #{report.total_urls}"
        puts "Archived URLs: #{report.archived_urls}"
        puts "Coverage: #{report.coverage_percent}%"
        puts "Missing: #{report.missing_count}"
        if report.has_gaps?
          puts "Temporal gaps:"
          report.temporal_gaps.each do |gap|
            puts "  #{gap[:from]} → #{gap[:to]} (#{gap[:gap_days]} days)"
          end
        end
        puts "Status distribution:"
        report.status_distribution.sort_by { |_, v| -v }.each do |code, count|
          puts "  #{code}: #{count}"
        end
      end
    end

    def output_snapshot_diff(diff)
      case options[:format]
      when "json"
        puts JSON.generate(diff.as_json)
      else
        puts "Comparing #{diff.to_h[:timestamp_a]} vs #{diff.to_h[:timestamp_b]}"
        puts "Content changed: #{diff.content_changed? ? 'Yes' : 'No'}"
        link_changes = diff.link_changes
        puts "Links added: #{link_changes[:added].size}"
        puts "Links removed: #{link_changes[:removed].size}"
        asset_changes = diff.asset_changes
        puts "Assets added: #{asset_changes[:added].size}"
        puts "Assets removed: #{asset_changes[:removed].size}"
        structural = diff.structural_changes
        unless structural.empty?
          puts "Structural changes:"
          structural.each do |tag, change|
            puts "  <#{tag}>: #{change[:from]} → #{change[:to]}"
          end
        end
      end
    end

    def output_search_results(results)
      case options[:format]
      when "json"
        puts JSON.generate(results.map(&:as_json))
      else
        if results.empty?
          warn "No results found."
          return
        end
        results.each do |result|
          puts "#{result.snapshot.timestamp} #{result.url}"
          puts "  #{result.context}"
          puts
        end
        warn "#{results.size} result(s) found."
      end
    end

    def output_content_changes(report)
      case options[:format]
      when "json"
        puts JSON.generate(report.as_json)
      else
        puts "URL: #{report.url}"
        puts "Total snapshots: #{report.total_snapshots}"
        puts "Unique digests: #{report.unique_digests}"
        puts "URLs changed: #{report.changed_urls.size}"
        puts "URLs added: #{report.new_urls.size}"
        puts "URLs removed: #{report.removed_urls.size}"
        unless report.changed_urls.empty?
          puts "Changed URLs:"
          report.changed_urls.each { |u| puts "  #{u}" }
        end
        unless report.new_urls.empty?
          puts "New URLs:"
          report.new_urls.each { |u| puts "  + #{u}" }
        end
        unless report.removed_urls.empty?
          puts "Removed URLs:"
          report.removed_urls.each { |u| puts "  - #{u}" }
        end
      end
    end

    def build_color
      ColorOutput.new(enabled: !options[:no_color])
    end
  end
end
