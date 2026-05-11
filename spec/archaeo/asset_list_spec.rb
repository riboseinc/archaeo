# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::AssetList do
  subject(:list) { described_class.new }

  describe "#add" do
    it "adds URLs by type" do
      list.add("style.css", type: :css)
      list.add("app.js", type: :js)
      list.add("logo.png", type: :image)

      expect(list.css).to eq(["style.css"])
      expect(list.js).to eq(["app.js"])
      expect(list.images).to eq(["logo.png"])
    end

    it "ignores nil URLs" do
      list.add(nil, type: :css)
      expect(list.css).to be_empty
    end

    it "ignores empty URLs" do
      list.add("", type: :css)
      expect(list.css).to be_empty
    end
  end

  describe "#all" do
    it "returns all URLs across types" do
      list.add("style.css", type: :css)
      list.add("app.js", type: :js)
      list.add("logo.png", type: :image)

      expect(list.all).to contain_exactly("style.css", "app.js", "logo.png")
    end

    it "deduplicates across types" do
      list.add("shared.css", type: :css)
      list.add("shared.css", type: :font)

      expect(list.all).to eq(["shared.css"])
    end
  end

  describe "#size" do
    it "returns the count of unique URLs" do
      list.add("a.css", type: :css)
      list.add("b.js", type: :js)
      list.add("c.png", type: :image)

      expect(list.size).to eq(3)
    end
  end

  describe "#empty?" do
    it "returns true when no assets" do
      expect(list).to be_empty
    end

    it "returns false when assets exist" do
      list.add("style.css", type: :css)
      expect(list).not_to be_empty
    end
  end

  describe "category accessors" do
    it "returns fonts" do
      list.add("font.woff2", type: :font)
      expect(list.fonts).to eq(["font.woff2"])
    end

    it "returns media" do
      list.add("video.mp4", type: :media)
      expect(list.media).to eq(["video.mp4"])
    end
  end

  describe "#filter" do
    it "returns a new list with only specified types" do
      list.add("style.css", type: :css)
      list.add("app.js", type: :js)
      list.add("logo.png", type: :image)

      filtered = list.filter(:css, :js)
      expect(filtered.all).to contain_exactly("style.css", "app.js")
      expect(filtered.images).to be_empty
    end
  end

  describe "#merge" do
    it "merges another AssetList" do
      list.add("style.css", type: :css)
      other = described_class.new
      other.add("app.js", type: :js)
      list.merge(other)
      expect(list.all).to contain_exactly("style.css", "app.js")
    end

    it "deduplicates on merge" do
      list.add("shared.css", type: :css)
      other = described_class.new
      other.add("shared.css", type: :css)
      list.merge(other)
      expect(list.css).to eq(["shared.css"])
    end
  end

  describe "#domain_counts" do
    it "counts URLs by domain" do
      list.add("https://cdn.example.com/style.css", type: :css)
      list.add("https://cdn.example.com/app.js", type: :js)
      list.add("https://other.com/logo.png", type: :image)

      counts = list.domain_counts
      expect(counts["cdn.example.com"]).to eq(2)
      expect(counts["other.com"]).to eq(1)
    end

    it "handles relative URLs" do
      list.add("/style.css", type: :css)
      counts = list.domain_counts
      expect(counts["(relative)"]).to eq(1)
    end
  end

  describe "#downloadable" do
    it "excludes data: URLs" do
      list.add("https://example.com/style.css", type: :css)
      list.add("data:image/png;base64,abc123", type: :image)
      downloadable = list.downloadable
      expect(downloadable.all).to eq(["https://example.com/style.css"])
    end

    it "excludes fragment-only URLs" do
      list.add("https://example.com/style.css", type: :css)
      list.add("#section", type: :image)
      downloadable = list.downloadable
      expect(downloadable.all).to eq(["https://example.com/style.css"])
    end
  end

  describe ".from_json" do
    it "reconstructs an AssetList from JSON" do
      json = '{"css":["style.css"],"js":["app.js"],"image":["logo.png"]}'
      list = described_class.from_json(json)
      expect(list.css).to eq(["style.css"])
      expect(list.js).to eq(["app.js"])
      expect(list.images).to eq(["logo.png"])
    end
  end
end
