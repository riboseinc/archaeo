# frozen_string_literal: true

require "digest"
require "set"

module Archaeo
  # Value object summarizing content changes for a URL over a time range.
  ContentChangeReport = Struct.new(
    :url, :from, :to,
    :changed_urls, :new_urls, :removed_urls,
    :content_frequency, :total_snapshots, :unique_digests,
    keyword_init: true
  ) do
    def any_changes?
      !changed_urls.empty? || !new_urls.empty? || !removed_urls.empty?
    end

    def to_h
      {
        url: url,
        from: from.to_s,
        to: to.to_s,
        changed_urls: changed_urls,
        new_urls: new_urls,
        removed_urls: removed_urls,
        content_frequency: content_frequency,
        total_snapshots: total_snapshots,
        unique_digests: unique_digests,
      }
    end

    def as_json(*)
      to_h
    end
  end

  # Tracks content changes for a URL across archived snapshots.
  #
  # Groups snapshots by original URL, then analyzes how content
  # (identified by CDX digest) changed over the given time range.
  class ContentTracker
    def initialize(cdx_api: CdxApi.new, fetcher: Fetcher.new)
      @cdx = cdx_api
      @fetcher = fetcher
    end

    def track(url, from: nil, to: nil)
      url = UrlNormalizer.normalize(url)
      ts_from = from ? Timestamp.coerce(from) : nil
      ts_to = to ? Timestamp.coerce(to) : nil

      opts = {}
      opts[:from] = ts_from.to_s if ts_from
      opts[:to] = ts_to.to_s if ts_to

      snapshots = @cdx.snapshots(url, **opts)
        .select(&:success?).to_a

      grouped = group_by_url(snapshots)
      analyze(url, ts_from, ts_to, snapshots, grouped)
    end

    private

    def group_by_url(snapshots)
      snapshots.group_by(&:original_url)
    end

    def analyze(url, ts_from, ts_to, all_snapshots, grouped)
      changed = []
      new_urls = []
      removed = []
      frequency = {}

      sorted = all_snapshots.sort_by(&:timestamp)
      timestamps = sorted.map(&:timestamp).uniq

      grouped.each do |original_url, snaps|
        url_snaps = snaps.sort_by(&:timestamp)
        digests = url_snaps.map(&:digest).reject(&:empty?)

        if digests.uniq.size > 1
          changed << original_url
        end

        frequency[original_url] = digests.uniq.size
      end

      if timestamps.size >= 2
        first_half, second_half = split_by_time(sorted, timestamps)
        first_urls = Set.new(first_half.map(&:original_url))
        second_urls = Set.new(second_half.map(&:original_url))

        new_urls = (second_urls - first_urls).to_a.sort
        removed = (first_urls - second_urls).to_a.sort
      end

      ContentChangeReport.new(
        url: url,
        from: ts_from,
        to: ts_to,
        changed_urls: changed.sort,
        new_urls: new_urls,
        removed_urls: removed,
        content_frequency: frequency,
        total_snapshots: all_snapshots.size,
        unique_digests: all_snapshots.map(&:digest).reject(&:empty?).uniq.size,
      )
    end

    def split_by_time(snapshots, timestamps)
      mid = timestamps[timestamps.size / 2]
      first, second = snapshots.partition { |s| s.timestamp < mid }
      [first, second]
    end
  end
end
