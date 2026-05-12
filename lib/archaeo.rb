# frozen_string_literal: true

require_relative "archaeo/version"

# Archaeo provides a Ruby interface to the Internet Archive's Wayback Machine
# APIs, including the CDX Server API, Availability API, SavePageNow API,
# and content fetching.
module Archaeo
  class Error < StandardError; end
  class NoSnapshotFound < Error; end
  class BlockedSiteError < Error; end
  class RateLimitError < Error; end
  class MaximumRetriesExceeded < Error; end
  class ArchiveNotAvailable < Error; end
  class InvalidResponse < Error; end
  class SaveFailed < Error; end
  class IntegrityError < Error; end

  class FetchError < Error
    attr_reader :status_code, :url, :page

    def initialize(message, status_code:, url:, page:)
      super(message)
      @status_code = status_code
      @url = url
      @page = page
    end
  end

  autoload :Timestamp, "archaeo/timestamp"
  autoload :ArchiveUrl, "archaeo/archive_url"
  autoload :Snapshot, "archaeo/snapshot"
  autoload :Page, "archaeo/page"
  autoload :PageBundle, "archaeo/page_bundle"
  autoload :SaveResult, "archaeo/save_result"
  autoload :AvailabilityResult, "archaeo/availability_result"
  autoload :UrlNormalizer, "archaeo/url_normalizer"
  autoload :CdxFilter, "archaeo/cdx_filter"
  autoload :CdxTimeline, "archaeo/cdx_timeline"
  autoload :AssetList, "archaeo/asset_list"
  autoload :AssetExtractor, "archaeo/asset_extractor"
  autoload :UrlRewriter, "archaeo/url_rewriter"
  autoload :DownloadState, "archaeo/download_state"
  autoload :HttpClient, "archaeo/http_client"
  autoload :CdxApi, "archaeo/cdx_api"
  autoload :AvailabilityApi, "archaeo/availability_api"
  autoload :SaveApi, "archaeo/save_api"
  autoload :Fetcher, "archaeo/fetcher"
  autoload :BulkDownloader, "archaeo/bulk_downloader"
  autoload :Cli, "archaeo/cli"
  autoload :EncodingDetector, "archaeo/encoding_detector"
  autoload :PathSanitizer, "archaeo/path_sanitizer"
  autoload :RateLimiter, "archaeo/rate_limiter"
  autoload :PatternFilter, "archaeo/pattern_filter"
  autoload :CdxCache, "archaeo/cdx_cache"
  autoload :SubdomainDiscovery, "archaeo/subdomain_discovery"
  autoload :ArchiveHealthCheck, "archaeo/archive_health_check"
end
