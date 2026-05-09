# frozen_string_literal: true

require "csv"
require "json"
require "thor"

module Archaeo
  # Command-line interface powered by Thor.
  class Cli < Thor
    map %w[--version -v] => :version

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
      cdx = CdxApi.new
      opts = build_cdx_options(options)
      snaps = cdx.snapshots(url, **opts).to_a
      case options[:format]
      when "json" then output_json(snaps)
      when "csv" then output_csv(snaps)
      else output_table(snaps)
      end
    end

    desc "near URL TIMESTAMP",
         "Find the snapshot closest to a timestamp"
    def near(url, timestamp)
      snap = CdxApi.new.near(url, timestamp: timestamp)
      puts snap.archive_url
    end

    desc "oldest URL", "Find the oldest snapshot of a URL"
    def oldest(url)
      snap = CdxApi.new.oldest(url)
      puts snap.archive_url
    end

    desc "newest URL", "Find the newest snapshot of a URL"
    def newest(url)
      snap = CdxApi.new.newest(url)
      puts snap.archive_url
    end

    desc "available URL", "Check if a URL is archived"
    def available(url)
      result = AvailabilityApi.new.near(url)
      if result.available?
        puts "Available: #{result.archive_url}"
      else
        puts "Not available"
        exit 1
      end
    end

    desc "save URL", "Save a URL to the Wayback Machine"
    def save(url)
      result = SaveApi.new.save(url)
      label = result.cached? ? "Cached" : "Saved"
      puts "#{label}: #{result.archive_url}"
    end

    desc "fetch URL TIMESTAMP",
         "Fetch archived content for a URL at a timestamp"
    option :identity, type: :boolean, default: false,
                      desc: "Fetch raw (identity) content"
    option :output, desc: "Write content to file"
    def fetch(url, timestamp)
      page = Fetcher.new.fetch(
        url, timestamp: timestamp,
             identity: options[:identity]
      )

      if options[:output]
        write_output(options[:output], page.content)
      else
        $stdout.write(page.content)
      end
    end

    desc "download URL", "Download all archived snapshots of a URL"
    option :output, desc: "Output directory", default: "archive"
    option :from, desc: "Start timestamp (YYYYMMDDHHmmss)"
    option :to, desc: "End timestamp (YYYYMMDDHHmmss)"
    option :resume, type: :boolean, default: false,
                    desc: "Resume interrupted download"
    def download(url)
      downloader = BulkDownloader.new(output_dir: options[:output])

      downloader.download(
        url,
        from: options[:from],
        to: options[:to],
        resume: options[:resume],
      ) do |current, total, snap|
        warn "[#{current}/#{total}] " \
             "#{snap.timestamp} #{snap.original_url}"
      end
    end

    desc "known_urls DOMAIN",
         "List all known URLs for a domain"
    def known_urls(domain)
      CdxApi.new.known_urls(domain).each do |u|
        puts u
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
      data = snaps.map do |snap|
        {
          timestamp: snap.timestamp.to_s,
          status_code: snap.status_code,
          url: snap.original_url,
          archive_url: snap.archive_url,
        }
      end
      puts JSON.generate(data)
    end

    def output_csv(snaps)
      puts CSV.generate do |csv|
        csv << %w[timestamp status_code url archive_url]
        snaps.each do |snap|
          csv << [snap.timestamp.to_s, snap.status_code,
                  snap.original_url, snap.archive_url]
        end
      end
    end

    def write_output(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
      warn "Written to #{path}"
    end
  end
end
