# frozen_string_literal: true

module Archaeo
  # Rewrites Wayback Machine archive URLs to local file paths.
  #
  # Used for saving archived pages and their assets for offline
  # browsing. Converts absolute archive URLs into relative paths
  # rooted at a configurable local directory.
  class UrlRewriter
    def initialize(archive_prefix, local_prefix)
      @archive_prefix = archive_prefix.to_s
      @local_prefix = local_prefix.to_s
    end

    def rewrite(url)
      return url unless url.start_with?(@archive_prefix)

      relative = url.sub(@archive_prefix, "")
      File.join(@local_prefix, relative)
    end
  end
end
