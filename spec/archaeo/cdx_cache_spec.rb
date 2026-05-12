# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Archaeo::CdxCache do
  let(:tmpdir) { Dir.mktmpdir("archaeo-cache-test") }
  let(:snapshots) do
    [
      Archaeo::Snapshot.new(
        urlkey: "com,example)/", timestamp: "20220615000000",
        original_url: "https://example.com/", mimetype: "text/html",
        status_code: 200, digest: "abc123", length: "1234"
      ),
    ]
  end
  let(:cache) { described_class.new(tmpdir) }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#fetch" do
    it "caches and returns snapshots" do
      result = cache.fetch("example.com") { snapshots }
      expect(result.size).to eq(1)
      expect(result.first.original_url).to eq("https://example.com/")
    end

    it "returns cached results on second call" do
      call_count = 0
      cache.fetch("example.com") do
        call_count += 1
        snapshots
      end
      cache.fetch("example.com") do
        call_count += 1
        snapshots
      end
      expect(call_count).to eq(1)
    end

    it "caches different queries separately" do
      call_count = 0
      cache.fetch("example.com") do
        call_count += 1
        snapshots
      end
      cache.fetch("other.com") do
        call_count += 1
        snapshots
      end
      expect(call_count).to eq(2)
    end
  end

  describe "#cached?" do
    it "returns false before caching" do
      expect(cache.cached?("example.com")).to be false
    end

    it "returns true after caching" do
      cache.fetch("example.com") { snapshots }
      expect(cache.cached?("example.com")).to be true
    end
  end

  describe "#cache_key" do
    it "returns different keys for different URLs" do
      k1 = cache.cache_key("example.com")
      k2 = cache.cache_key("other.com")
      expect(k1).not_to eq(k2)
    end

    it "includes options in key" do
      k1 = cache.cache_key("example.com")
      k2 = cache.cache_key("example.com", from: "20220101")
      expect(k1).not_to eq(k2)
    end
  end

  describe "#clear" do
    it "clears specific cache entry" do
      cache.fetch("example.com") { snapshots }
      cache.clear("example.com")
      expect(cache.cached?("example.com")).to be false
    end

    it "clears all cache entries" do
      cache.fetch("example.com") { snapshots }
      cache.clear
      expect(cache.cached?("example.com")).to be false
    end
  end
end
