# frozen_string_literal: true

require "thor"

module Archaeo
  # Command-line interface powered by Thor.
  class Cli < Thor
    desc "snapshots URL", "List archived snapshots for a URL"
    option :from, desc: "Start timestamp (YYYYMMDDHHmmss)"
    option :to, desc: "End timestamp (YYYYMMDDHHmmss)"
    option :match_type,
           desc: "Match type (exact, prefix, host, domain)"
    option :filter, type: :array, desc: "CDX filter expressions"
    option :collapse, type: :array, desc: "CDX collapse fields"
    option :sort, desc: "Sort order (default, closest, reverse)"
    option :limit, type: :numeric, desc: "Max snapshots to return"
    def snapshots(url)
      cdx = CdxApi.new
      opts = build_cdx_options(options)
      cdx.snapshots(url, **opts).each do |snap|
        puts "#{snap.timestamp}  #{snap.status_code}  " \
             "#{snap.original_url}"
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
    def fetch(url, timestamp)
      page = Fetcher.new.fetch(
        url, timestamp: timestamp,
             identity: options[:identity]
      )
      $stdout.write(page.content)
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
  end
end
