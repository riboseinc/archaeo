# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::PageBundle do
  describe "#initialize" do
    it "stores page and assets" do
      page = Archaeo::Page.new(
        content: "<html></html>",
        content_type: "text/html",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/" \
                     "https://example.com/",
        original_url: "https://example.com/",
        timestamp: Archaeo::Timestamp.new(year: 2022, month: 6, day: 15),
      )
      assets = Archaeo::AssetList.new
      assets.add("/style.css", type: :css)

      bundle = described_class.new(page: page, assets: assets)
      expect(bundle.page).to eq(page)
      expect(bundle.assets).to eq(assets)
      expect(bundle.assets.css).to eq(["/style.css"])
    end
  end
end
