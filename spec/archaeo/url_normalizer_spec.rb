# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::UrlNormalizer do
  describe ".normalize" do
    it "strips leading and trailing whitespace" do
      expect(described_class.normalize("  https://example.com/  "))
        .to eq("https://example.com/")
    end

    it "strips surrounding double quotes" do
      expect(described_class.normalize('"https://example.com/"'))
        .to eq("https://example.com/")
    end

    it "strips surrounding single quotes" do
      expect(described_class.normalize("'https://example.com/'"))
        .to eq("https://example.com/")
    end

    it "fixes double percent encoding" do
      expect(described_class.normalize("https://example.com/%252F"))
        .to eq("https://example.com/%2F")
    end

    it "normalizes percent encoding to uppercase" do
      expect(described_class.normalize("https://example.com/%2f%3a"))
        .to eq("https://example.com/%2F%3A")
    end

    it "leaves already-normalized URLs unchanged" do
      url = "https://example.com/path%20here"
      expect(described_class.normalize(url)).to eq(url)
    end

    it "handles bare domains" do
      expect(described_class.normalize("example.com"))
        .to eq("example.com")
    end
  end

  describe ".with_scheme" do
    it "adds https:// to bare domains" do
      expect(described_class.with_scheme("example.com"))
        .to eq("https://example.com")
    end

    it "preserves existing https scheme" do
      expect(described_class.with_scheme("https://example.com"))
        .to eq("https://example.com")
    end

    it "preserves existing http scheme" do
      expect(described_class.with_scheme("http://example.com"))
        .to eq("http://example.com")
    end
  end

  describe "#normalized" do
    it "returns the normalized URL" do
      normalizer = described_class.new(" https://example.com/ ")
      expect(normalizer.normalized).to eq("https://example.com/")
    end
  end

  describe "#original" do
    it "returns the original URL" do
      normalizer = described_class.new(" https://example.com/ ")
      expect(normalizer.original).to eq(" https://example.com/ ")
    end
  end

  describe "#to_s" do
    it "returns the normalized URL" do
      normalizer = described_class.new(" https://example.com/ ")
      expect(normalizer.to_s).to eq("https://example.com/")
    end
  end
end
