# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::Snapshot do
  subject(:snapshot) do
    described_class.new(
      urlkey: "com,example)/",
      timestamp: "20220113130051",
      original_url: "https://example.com/",
      mimetype: "text/html",
      status_code: "200",
      digest: "SHA1-abc123",
      length: "12345",
    )
  end

  describe "#initialize" do
    it "stores all fields" do
      expect(snapshot.urlkey).to eq("com,example)/")
      expect(snapshot.original_url).to eq("https://example.com/")
      expect(snapshot.mimetype).to eq("text/html")
      expect(snapshot.status_code).to eq(200)
      expect(snapshot.digest).to eq("SHA1-abc123")
      expect(snapshot.length).to eq(12345)
    end

    it "converts timestamp string to Timestamp object" do
      expect(snapshot.timestamp).to be_a(Archaeo::Timestamp)
      expect(snapshot.timestamp.year).to eq(2022)
    end

    it "converts numeric fields to integers" do
      expect(snapshot.status_code).to be_a(Integer)
      expect(snapshot.length).to be_a(Integer)
    end
  end

  describe "#archive_url" do
    it "constructs the Wayback Machine archive URL" do
      expect(snapshot.archive_url)
        .to eq("https://web.archive.org/web/20220113130051/https://example.com/")
    end
  end

  it "accepts Timestamp objects for timestamp" do
    ts = Archaeo::Timestamp.new(year: 2020, month: 6, day: 15)
    snap = described_class.new(
      urlkey: "com,example)/",
      timestamp: ts,
      original_url: "https://example.com/",
      mimetype: "text/html",
      status_code: 200,
      digest: "SHA1-abc",
      length: 100,
    )
    expect(snap.timestamp).to equal(ts)
  end

  describe "equality and hash" do
    it "considers identical snapshots equal" do
      other = described_class.new(
        urlkey: "com,example)/",
        timestamp: "20220113130051",
        original_url: "https://example.com/",
      )
      same = described_class.new(
        urlkey: "com,example)/",
        timestamp: "20220113130051",
        original_url: "https://example.com/",
      )
      expect(other).to eq(same)
    end

    it "produces stable hashes for identical snapshots" do
      snap1 = described_class.new(
        urlkey: "com,example)/",
        timestamp: "20220113130051",
        original_url: "https://example.com/",
      )
      snap2 = described_class.new(
        urlkey: "com,example)/",
        timestamp: "20220113130051",
        original_url: "https://example.com/",
      )
      expect(snap1.hash).to eq(snap2.hash)
    end
  end

  describe "#blocked?" do
    it "returns true when status code is -1" do
      snap = described_class.new(
        urlkey: "com,example)/",
        timestamp: "20220113130051",
        original_url: "https://example.com/",
        status_code: "-1",
      )
      expect(snap).to be_blocked
    end

    it "returns false for normal status codes" do
      expect(snapshot).not_to be_blocked
    end
  end

  describe "#to_a" do
    it "returns all field values in order" do
      arr = snapshot.to_a
      expect(arr[0]).to eq("com,example)/")
      expect(arr[1]).to be_a(Archaeo::Timestamp)
      expect(arr[2]).to eq("https://example.com/")
      expect(arr[3]).to eq("text/html")
      expect(arr[4]).to eq(200)
      expect(arr[5]).to eq("SHA1-abc123")
      expect(arr[6]).to eq(12345)
    end
  end

  describe "#to_h" do
    it "returns a hash with named fields" do
      h = snapshot.to_h
      expect(h[:urlkey]).to eq("com,example)/")
      expect(h[:timestamp]).to be_a(Archaeo::Timestamp)
      expect(h[:original_url]).to eq("https://example.com/")
      expect(h[:mimetype]).to eq("text/html")
      expect(h[:status_code]).to eq(200)
      expect(h[:digest]).to eq("SHA1-abc123")
      expect(h[:length]).to eq(12345)
    end
  end

  describe "#success?" do
    it "returns true for status code 200" do
      expect(snapshot).to be_success
    end

    it "returns false for other status codes" do
      snap = described_class.new(
        urlkey: "com,example)/",
        timestamp: "20220113130051",
        original_url: "https://example.com/",
        status_code: "404",
      )
      expect(snap).not_to be_success
    end
  end
end
