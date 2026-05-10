# frozen_string_literal: true

module Archaeo
  # A fetched page together with all its extracted asset URLs.
  #
  # Bundles a Page with the AssetList discovered from its HTML,
  # providing a single object for complete page archival.
  class PageBundle
    include Enumerable

    attr_reader :page, :assets

    def initialize(page:, assets:)
      @page = page
      @assets = assets
    end

    def each(&block)
      assets.each(&block)
    end

    def size
      assets.size + 1
    end

    def asset_count
      assets.size
    end
  end
end
