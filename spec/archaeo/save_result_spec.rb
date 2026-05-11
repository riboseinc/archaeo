# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::SaveResult do
  subject do
    described_class.new(
      url: "https://example.com/",
      archive_url: "https://web.archive.org/web/20220615120000/" \
                   "https://example.com/",
      timestamp: ts,
      cached: false,
    )
  end

  let(:ts) { Archaeo::Timestamp.new(year: 2022, month: 6, day: 15) }

  it "exposes archive_url" do
    expect(subject.archive_url).to include("web.archive.org")
  end

  it "exposes timestamp as a Timestamp" do
    expect(subject.timestamp).to be_a(Archaeo::Timestamp)
  end

  it "reports cached status" do
    expect(subject).not_to be_cached
  end

  it "reports cached true when appropriate" do
    result = described_class.new(
      url: "https://example.com/",
      archive_url: "https://web.archive.org/web/20220615120000/" \
                   "https://example.com/",
      timestamp: ts,
      cached: true,
    )
    expect(result).to be_cached
  end

  it "exposes url" do
    expect(subject.url).to eq("https://example.com/")
  end

  describe "#to_h" do
    it "returns a hash with all fields" do
      h = subject.to_h
      expect(h[:url]).to eq("https://example.com/")
      expect(h[:cached]).to be(false)
    end
  end

  describe "#as_json" do
    it "returns a JSON-serializable hash" do
      h = subject.as_json
      expect(h[:timestamp]).to eq("20220615000000")
      expect { JSON.generate(h) }.not_to raise_error
    end
  end

  describe "#to_s" do
    it "shows Saved for new saves" do
      expect(subject.to_s).to start_with("Saved:")
    end

    it "shows Cached for cached results" do
      result = described_class.new(
        url: "https://example.com/",
        archive_url: "https://web.archive.org/web/20220615120000/https://example.com/",
        timestamp: ts, cached: true
      )
      expect(result.to_s).to start_with("Cached:")
    end
  end

  describe "#inspect" do
    it "shows class, url and cached status" do
      expect(subject.inspect).to include("example.com")
      expect(subject.inspect).to include("cached=false")
    end
  end

  describe "#success?" do
    it "returns true when archive_url is present" do
      expect(subject).to be_success
    end

    it "returns false when archive_url is nil" do
      result = described_class.new(
        url: "https://example.com/",
        archive_url: nil, timestamp: nil, cached: false
      )
      expect(result).not_to be_success
    end
  end

  describe "nil timestamp handling" do
    it "accepts nil timestamp without error" do
      result = described_class.new(
        url: "https://example.com/",
        archive_url: nil, timestamp: nil, cached: false
      )
      expect(result.timestamp).to be_nil
    end
  end
end
