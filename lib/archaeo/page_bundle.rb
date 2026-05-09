# frozen_string_literal: true

module Archaeo
  # A fetched page together with all its extracted asset URLs.
  #
  # Bundles a Page with the AssetList discovered from its HTML,
  # providing a single object for complete page archival.
  class PageBundle
    attr_reader :page, :assets

    def initialize(page:, assets:)
      @page = page
      @assets = assets
    end
  end
end
