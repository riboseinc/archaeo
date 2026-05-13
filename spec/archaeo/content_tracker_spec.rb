# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::ContentTracker do
  let(:snapshots) do
    [
      Archaeo::Snapshot.new(
        urlkey: "com,example)/",
        timestamp: "20220101000000",
        original_url: "https://example.com/",
        mimetype: "text/html", status_code: 200,
        digest: "SHA1-aaa", length: 100
      ),
      Archaeo::Snapshot.new(
        urlkey: "com,example)/",
        timestamp: "20220601000000",
        original_url: "https://example.com/",
        mimetype: "text/html", status_code: 200,
        digest: "SHA1-bbb", length: 120
      ),
      Archaeo::Snapshot.new(
        urlkey: "com,example)/about",
        timestamp: "20220615000000",
        original_url: "https://example.com/about",
        mimetype: "text/html", status_code: 200,
        digest: "SHA1-ccc", length: 80
      ),
    ]
  end

  let(:fake_cdx) do
    cdx = instance_double(Archaeo::CdxApi)
    allow(cdx).to receive(:snapshots).and_return(snapshots)
    cdx
  end

  let(:tracker) { described_class.new(cdx_api: fake_cdx) }

  it "detects changed URLs" do
    report = tracker.track("example.com")
    expect(report.changed_urls).to include("https://example.com/")
  end

  it "identifies new URLs in second half" do
    report = tracker.track("example.com")
    expect(report.new_urls).to include("https://example.com/about")
  end

  it "reports total snapshots" do
    report = tracker.track("example.com")
    expect(report.total_snapshots).to eq(3)
  end

  it "reports unique digests" do
    report = tracker.track("example.com")
    expect(report.unique_digests).to eq(3)
  end

  it "reports content frequency per URL" do
    report = tracker.track("example.com")
    expect(report.content_frequency["https://example.com/"]).to eq(2)
  end

  it "serializes to hash" do
    report = tracker.track("example.com")
    h = report.to_h
    expect(h[:url]).to include("example.com")
    expect(h[:changed_urls]).to be_a(Array)
  end

  it "serializes to JSON" do
    report = tracker.track("example.com")
    json = report.as_json
    expect(json).to be_a(Hash)
    expect { JSON.generate(json) }.not_to raise_error
  end

  it "detects any_changes" do
    report = tracker.track("example.com")
    expect(report.any_changes?).to be true
  end
end

RSpec.describe Archaeo::ContentChangeReport do
  it "detects no changes" do
    report = described_class.new(
      url: "https://example.com/",
      from: nil, to: nil,
      changed_urls: [], new_urls: [], removed_urls: [],
      content_frequency: {}, total_snapshots: 1, unique_digests: 1
    )
    expect(report.any_changes?).to be false
  end
end
