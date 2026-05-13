# frozen_string_literal: true

module Archaeo
  # Analyzes how thoroughly a site was archived by the Wayback Machine.
  #
  # Produces coverage statistics including total URLs, archived URLs,
  # coverage percentage, temporal gaps, and status distribution.
  class CoverageReport
    attr_reader :url, :total_urls, :archived_urls, :status_distribution,
                :temporal_gaps, :missing_assets

    def initialize(url:, total_urls:, archived_urls:,
                   status_distribution: {}, temporal_gaps: [],
                   missing_assets: [])
      @url = url
      @total_urls = total_urls
      @archived_urls = archived_urls
      @status_distribution = status_distribution
      @temporal_gaps = temporal_gaps
      @missing_assets = missing_assets
    end

    def coverage_percent
      return 0.0 if total_urls.zero?

      (archived_urls.to_f / total_urls * 100).round(1)
    end

    def missing_count
      total_urls - archived_urls
    end

    def has_gaps?
      !temporal_gaps.empty?
    end

    def to_h
      {
        url: @url,
        total_urls: @total_urls,
        archived_urls: @archived_urls,
        coverage_percent: coverage_percent,
        missing_count: missing_count,
        status_distribution: @status_distribution,
        temporal_gaps: @temporal_gaps,
        missing_assets: @missing_assets,
      }
    end

    def as_json(*)
      to_h
    end
  end
end
