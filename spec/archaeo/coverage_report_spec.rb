# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::CoverageReport do
  describe "coverage metrics" do
    let(:report) do
      described_class.new(
        url: "example.com",
        total_urls: 100,
        archived_urls: 87,
        status_distribution: { 200 => 80, 404 => 10, 301 => 10 },
        temporal_gaps: [{ from: "20220301", to: "20220601", gap_days: 92 }],
      )
    end

    it "computes coverage percent" do
      expect(report.coverage_percent).to eq(87.0)
    end

    it "computes missing count" do
      expect(report.missing_count).to eq(13)
    end

    it "detects temporal gaps" do
      expect(report.has_gaps?).to be true
    end

    it "serializes to hash" do
      h = report.to_h
      expect(h[:coverage_percent]).to eq(87.0)
      expect(h[:status_distribution][200]).to eq(80)
    end
  end

  describe "edge cases" do
    it "handles zero total URLs" do
      report = described_class.new(
        url: "empty.com", total_urls: 0, archived_urls: 0,
      )
      expect(report.coverage_percent).to eq(0.0)
      expect(report.missing_count).to eq(0)
    end

    it "handles no gaps" do
      report = described_class.new(
        url: "full.com", total_urls: 10, archived_urls: 10,
      )
      expect(report.has_gaps?).to be false
    end
  end
end

RSpec.describe Archaeo::CoverageAnalyzer do
  describe "#analyze" do
    it "produces a coverage report from snapshots" do
      snapshots = [
        build_snap("20220101", 200),
        build_snap("20220201", 200),
        build_snap("20220301", 404),
      ]
      fake_cdx = FakeCdxApiWithSnapshots.new(snapshots)
      analyzer = described_class.new(cdx_api: fake_cdx)
      report = analyzer.analyze("example.com")

      expect(report).to be_a(Archaeo::CoverageReport)
      expect(report.archived_urls).to be >= 1
      expect(report.status_distribution[200]).to be >= 1
    end
  end

  private

  def build_snap(ts, status)
    Archaeo::Snapshot.new(
      urlkey: "com,example)/", timestamp: ts,
      original_url: "https://example.com/", mimetype: "text/html",
      status_code: status, digest: "abc#{ts}", length: "1000"
    )
  end
end
