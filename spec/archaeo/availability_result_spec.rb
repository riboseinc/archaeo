# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::AvailabilityResult do
  let(:ts) { Archaeo::Timestamp.new(year: 2022, month: 1, day: 13) }

  it "reports available when archive exists" do
    result = described_class.new(
      url: "example.com",
      available: true,
      archive_url: "https://web.archive.org/web/20220113130051/" \
                   "https://example.com/",
      timestamp: ts,
    )
    expect(result).to be_available
    expect(result.url).to eq("example.com")
    expect(result.archive_url).to include("web.archive.org")
    expect(result.timestamp).to be_a(Archaeo::Timestamp)
  end

  it "reports unavailable when no archive exists" do
    result = described_class.new(url: "example.com",
                                 available: false)
    expect(result).not_to be_available
    expect(result).to be_unavailable
    expect(result.archive_url).to be_nil
    expect(result.timestamp).to be_nil
  end

  it "exposes archived_status" do
    result = described_class.new(
      url: "example.com", available: true,
      archived_status: 404
    )
    expect(result.archived_status).to eq(404)
  end

  it "provides to_s" do
    result = described_class.new(
      url: "example.com", available: true,
      archive_url: "https://web.archive.org/web/20220113130051/https://example.com/",
      timestamp: ts
    )
    expect(result.to_s).to include("example.com")
    expect(result.to_s).to include("web.archive.org")
  end

  describe "#to_h" do
    it "returns a hash with all fields" do
      result = described_class.new(
        url: "example.com", available: true,
        archive_url: "https://web.archive.org/web/20220113130051/https://example.com/",
        timestamp: ts
      )
      h = result.to_h
      expect(h[:url]).to eq("example.com")
      expect(h[:available]).to be(true)
    end
  end

  describe "#as_json" do
    it "returns a JSON-serializable hash" do
      result = described_class.new(
        url: "example.com", available: true,
        archive_url: "https://web.archive.org/web/20220113130051/https://example.com/",
        timestamp: ts
      )
      h = result.as_json
      expect(h[:timestamp]).to eq("20220113000000")
      expect { JSON.generate(h) }.not_to raise_error
    end
  end

  describe "#inspect" do
    it "shows class, url and availability" do
      result = described_class.new(url: "example.com", available: true)
      expect(result.inspect).to include("example.com")
      expect(result.inspect).to include("available=true")
    end
  end

  describe "#to_snapshot" do
    it "returns a Snapshot when available" do
      result = described_class.new(
        url: "https://example.com/", available: true,
        archive_url: "https://web.archive.org/web/20220113130051/https://example.com/",
        timestamp: ts, archived_status: 200
      )
      snap = result.to_snapshot
      expect(snap).to be_a(Archaeo::Snapshot)
      expect(snap.original_url).to eq("https://example.com/")
      expect(snap.status_code).to eq(200)
    end

    it "returns nil when unavailable" do
      result = described_class.new(url: "example.com", available: false)
      expect(result.to_snapshot).to be_nil
    end

    it "defaults status_code to 200 when archived_status is nil" do
      result = described_class.new(
        url: "https://example.com/", available: true,
        archive_url: "https://web.archive.org/web/20220113130051/https://example.com/",
        timestamp: ts
      )
      snap = result.to_snapshot
      expect(snap.status_code).to eq(200)
    end
  end
end
