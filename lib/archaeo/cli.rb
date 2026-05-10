# frozen_string_literal: true

require "csv"
require "json"
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

      warn "Downloaded #{summary.downloaded}/#{summary.total} " \
           "(#{summary.bytes_written} bytes) in " \
           "#{summary.elapsed.round(1)}s"
    end

    def build_cdx_options(opts)
      CDX_OPTION_MAP.each_with_object({}) do |(cli_key, api_key), result|
        value = opts[cli_key]
        result[api_key] = value if value
      end
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
  end
end
