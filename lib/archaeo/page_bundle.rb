# frozen_string_literal: true

require "json"

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

    def to_h
      { page: @page.to_h, assets: @assets.to_h }
    end

    def as_json(*)
      { page: @page.as_json, assets: @assets.to_h }
    end

    def to_json(*args)
      JSON.generate(as_json, *args)
    end

    def download_assets(output_dir:, client: HttpClient.new)
      FileUtils.mkdir_p(output_dir)
      @assets.all.each do |url|
        filename = File.join(output_dir,
                             File.basename(URI.parse(url).path))
        tmp_path = "#{filename}.tmp"
        response = client.get(url)
        File.binwrite(tmp_path, response.body)
        File.rename(tmp_path, filename)
      rescue StandardError
        FileUtils.rm_f(tmp_path) if defined?(tmp_path)
      end
    end
  end
end
