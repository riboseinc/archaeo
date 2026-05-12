# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::ProgressReport do
  describe "computed metrics" do
    let(:report) do
      described_class.new(
        current: 50, total: 100,
        downloaded_bytes: 1024 * 1024,
        elapsed: 10.0,
        current_url: "https://example.com/page.html"
      )
    end

    it "computes percent complete" do
      expect(report.percent_complete).to eq(50.0)
    end

    it "computes download speed" do
      expect(report.speed).to be_within(100).of(104_857.6)
    end

    it "computes ETA" do
      expect(report.eta).to be_within(0.1).of(10.0)
    end

    it "returns current_url" do
      expect(report.current_url).to eq("https://example.com/page.html")
    end

    it "serializes to hash" do
      h = report.to_h
      expect(h[:current]).to eq(50)
      expect(h[:percent_complete]).to eq(50.0)
      expect(h[:downloaded_bytes]).to eq(1024 * 1024)
    end

    it "serializes to JSON-friendly hash" do
      json = report.as_json
      expect(json[:current]).to eq(50)
    end
  end

  describe "edge cases" do
    it "returns 0% for zero total" do
      report = described_class.new(current: 0, total: 0,
                                   downloaded_bytes: 0, elapsed: 1.0)
      expect(report.percent_complete).to eq(0.0)
    end

    it "returns 0.0 speed for zero elapsed" do
      report = described_class.new(current: 10, total: 100,
                                   downloaded_bytes: 1000, elapsed: 0)
      expect(report.speed).to eq(0.0)
    end

    it "returns nil ETA with no progress data" do
      report = described_class.new(current: 0, total: 100,
                                   downloaded_bytes: 0, elapsed: 0)
      expect(report.eta).to be_nil
    end
  end
end
