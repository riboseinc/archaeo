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
end
