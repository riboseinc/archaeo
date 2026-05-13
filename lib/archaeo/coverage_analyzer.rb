# frozen_string_literal: true

module Archaeo
  # Builds a CoverageReport from CDX snapshot data.
  class CoverageAnalyzer
    def initialize(cdx_api: nil)
      @cdx_api = cdx_api
    end

    def analyze(url, from: nil, to: nil)
      cdx = @cdx_api || CdxApi.new
      snapshots = cdx.snapshots(url, from: from, to: to).to_a

      unique_urls = snapshots.map(&:original_url).uniq
      status_dist = compute_status_distribution(snapshots)
      gaps = compute_temporal_gaps(snapshots)

      CoverageReport.new(
        url: url,
        total_urls: unique_urls.size,
        archived_urls: snapshots.count(&:success?),
        status_distribution: status_dist,
        temporal_gaps: gaps,
      )
    end

    private

    def compute_status_distribution(snapshots)
      snapshots.each_with_object(Hash.new(0)) do |snap, counts|
        counts[snap.status_code] += 1
      end
    end

    def compute_temporal_gaps(snapshots)
      return [] if snapshots.size < 2

      sorted = snapshots.sort_by(&:timestamp)
      gaps = []
      sorted.each_cons(2) do |a, b|
        diff_days = (b.timestamp.to_time - a.timestamp.to_time) / 86400
        next unless diff_days > 30

        gaps << { from: a.timestamp.to_s, to: b.timestamp.to_s,
                  gap_days: diff_days.round }
      end
      gaps
    end
  end
end
