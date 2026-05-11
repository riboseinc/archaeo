# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::CdxTimeline do
  let(:snapshots) do
    [
      Archaeo::Snapshot.new(
        urlkey: "com,example)/", timestamp: "20220113130051",
        original_url: "https://example.com/"
      ),
      Archaeo::Snapshot.new(
        urlkey: "com,example)/", timestamp: "20220115120000",
        original_url: "https://example.com/"
      ),
      Archaeo::Snapshot.new(
        urlkey: "com,example)/", timestamp: "20220601120000",
        original_url: "https://example.com/"
      ),
    ]
  end

  describe "bucket grouping" do
    it "groups by month by default" do
      timeline = described_class.new(snapshots)
      result = timeline.to_h
      expect(result["202201"]).to eq(2)
      expect(result["202206"]).to eq(1)
    end

    it "groups by year" do
      timeline = described_class.new(snapshots, bucket_size: :year)
      result = timeline.to_h
      expect(result["2022"]).to eq(3)
    end

    it "groups by day" do
      timeline = described_class.new(snapshots, bucket_size: :day)
      result = timeline.to_h
      expect(result["20220113"]).to eq(1)
      expect(result["20220115"]).to eq(1)
      expect(result["20220601"]).to eq(1)
    end

    it "groups by week" do
      timeline = described_class.new(snapshots, bucket_size: :week)
      expect(timeline.size).to be >= 2
    end
  end

  describe "#to_a" do
    it "returns sorted buckets" do
      timeline = described_class.new(snapshots)
      arr = timeline.to_a
      expect(arr.map(&:first)).to eq(%w[202201 202206])
    end
  end

  describe "#peak" do
    it "returns the bucket with the most snapshots" do
      timeline = described_class.new(snapshots)
      peak = timeline.peak
      expect(peak[0]).to eq("202201")
      expect(peak[1]).to eq(2)
    end
  end

  describe "#total" do
    it "returns the total number of snapshots" do
      timeline = described_class.new(snapshots)
      expect(timeline.total).to eq(3)
    end
  end

  describe "#span" do
    it "returns first and last bucket keys" do
      timeline = described_class.new(snapshots)
      expect(timeline.span).to eq(%w[202201 202206])
    end

    it "returns nil when empty" do
      timeline = described_class.new([])
      expect(timeline.span).to be_nil
    end
  end

  describe "#empty?" do
    it "returns true when no snapshots" do
      timeline = described_class.new([])
      expect(timeline).to be_empty
    end

    it "returns false when snapshots exist" do
      timeline = described_class.new(snapshots)
      expect(timeline).not_to be_empty
    end
  end

  describe "#size" do
    it "returns the number of buckets" do
      timeline = described_class.new(snapshots)
      expect(timeline.size).to eq(2)
    end
  end

  describe "#inspect" do
    it "shows snapshot count and bucket count" do
      timeline = described_class.new(snapshots)
      expect(timeline.inspect).to eq(
        "#<Archaeo::CdxTimeline 3 snapshots in 2 buckets>",
      )
    end
  end
end
