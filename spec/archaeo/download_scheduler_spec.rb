# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::DownloadScheduler do
  let(:snaps) do
    [
      snap_at("20220101", "text/html", "https://example.com/", 1000),
      snap_at("20220301", "text/css", "https://example.com/style.css", 500),
      snap_at("20220601", "text/html", "https://example.com/deep/page", 2000),
      snap_at("20220115", "image/png", "https://example.com/img.png", 3000),
    ]
  end

  describe "#schedule" do
    it "orders newest_first by default" do
      scheduler = described_class.new
      result = scheduler.schedule(snaps)
      timestamps = result.map { |s| s.timestamp.to_s }
      expect(timestamps).to eq(%w[20220601000000 20220301000000 20220115000000
                                  20220101000000])
    end

    it "orders oldest_first" do
      scheduler = described_class.new(strategy: :oldest_first)
      result = scheduler.schedule(snaps)
      timestamps = result.map { |s| s.timestamp.to_s }
      expect(timestamps).to eq(%w[20220101000000 20220115000000 20220301000000
                                  20220601000000])
    end

    it "orders breadth_first by path depth" do
      scheduler = described_class.new(strategy: :breadth_first)
      result = scheduler.schedule(snaps)
      urls = result.map(&:original_url)
      # / and /style.css and /img.png have fewer segments than /deep/page
      shallow = urls.take(3).sort
      deep = urls.last
      expect(shallow).to include("https://example.com/")
      expect(deep).to eq("https://example.com/deep/page")
    end

    it "orders depth_first by path depth" do
      scheduler = described_class.new(strategy: :depth_first)
      result = scheduler.schedule(snaps)
      urls = result.map(&:original_url)
      expect(urls.first).to eq("https://example.com/deep/page")
    end

    it "raises for invalid strategy" do
      expect { described_class.new(strategy: :invalid) }
        .to raise_error(ArgumentError, /Invalid strategy/)
    end
  end

  describe "priority" do
    it "prioritizes html_first" do
      scheduler = described_class.new(priority: :html_first)
      result = scheduler.schedule(snaps)
      mimes = result.map(&:mimetype)
      html_count = mimes.count { |m| m.include?("text/html") }
      expect(mimes.first(html_count).all? { |m| m.include?("text/html") })
        .to be true
    end

    it "prioritizes smallest_first" do
      scheduler = described_class.new(priority: :smallest_first)
      result = scheduler.schedule(snaps)
      sizes = result.map(&:length)
      expect(sizes.each_cons(2).all? { |a, b| a <= b }).to be true
    end

    it "prioritizes largest_first" do
      scheduler = described_class.new(priority: :largest_first)
      result = scheduler.schedule(snaps)
      sizes = result.map(&:length)
      expect(sizes.each_cons(2).all? { |a, b| a >= b }).to be true
    end

    it "raises for invalid priority" do
      expect { described_class.new(priority: :invalid) }
        .to raise_error(ArgumentError, /Invalid priority/)
    end
  end

  describe "size filters" do
    it "filters by max_file_size" do
      scheduler = described_class.new(max_file_size: 1500)
      result = scheduler.schedule(snaps)
      expect(result.all? { |s| s.length <= 1500 }).to be true
    end

    it "filters by min_file_size" do
      scheduler = described_class.new(min_file_size: 800)
      result = scheduler.schedule(snaps)
      expect(result.all? { |s| s.length >= 800 }).to be true
    end
  end

  private

  def snap_at(ts, mime, url, length)
    Archaeo::Snapshot.new(
      urlkey: "com,example)/", timestamp: ts,
      original_url: url, mimetype: mime,
      status_code: 200, digest: "abc", length: length.to_s
    )
  end
end
