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

  autoload :Timestamp, "archaeo/timestamp"
  autoload :ArchiveUrl, "archaeo/archive_url"
  autoload :Snapshot, "archaeo/snapshot"
  autoload :Page, "archaeo/page"
  autoload :SaveResult, "archaeo/save_result"
  autoload :AvailabilityResult, "archaeo/availability_result"
  autoload :HttpClient, "archaeo/http_client"
  autoload :CdxApi, "archaeo/cdx_api"
  autoload :AvailabilityApi, "archaeo/availability_api"
  autoload :SaveApi, "archaeo/save_api"
  autoload :Fetcher, "archaeo/fetcher"
  autoload :Cli, "archaeo/cli"
end
