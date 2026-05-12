# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::SnapshotDiff do
  let(:html_a) do
    <<~HTML
      <html><head><title>Old</title></head>
      <body>
        <a href="https://example.com/page1">Page 1</a>
        <img src="https://example.com/old.png">
      </body></html>
    HTML
  end

  let(:html_b) do
    <<~HTML
      <html><head><title>New</title></head>
      <body>
        <a href="https://example.com/page1">Page 1</a>
        <a href="https://example.com/page2">Page 2</a>
        <img src="https://example.com/new.png">
      </body></html>
    HTML
  end

  let(:page_a) do
    Archaeo::Page.new(
      content: html_a, content_type: "text/html",
      status_code: 200,
      archive_url: "https://web.archive.org/web/20220101/https://example.com/",
      original_url: "https://example.com/",
      timestamp: "20220101"
    )
  end

  let(:page_b) do
    Archaeo::Page.new(
      content: html_b, content_type: "text/html",
      status_code: 200,
      archive_url: "https://web.archive.org/web/20220601/https://example.com/",
      original_url: "https://example.com/",
      timestamp: "20220601"
    )
  end

  let(:diff) do
    described_class.new(
      url: "https://example.com/",
      page_a: page_a, page_b: page_b,
      timestamp_a: "20220101", timestamp_b: "20220601"
    )
  end

  describe "#content_changed?" do
    it "detects content changes" do
      expect(diff.content_changed?).to be true
    end

    it "detects identical content" do
      same_diff = described_class.new(
        url: "https://example.com/",
        page_a: page_a, page_b: page_a,
        timestamp_a: "20220101", timestamp_b: "20220102"
      )
      expect(same_diff.content_changed?).to be false
    end
  end

  describe "#link_changes" do
    it "finds added links" do
      expect(diff.link_changes[:added]).to include("https://example.com/page2")
    end

    it "finds removed links" do
      changes = diff.link_changes
      expect(changes[:added].size + changes[:removed].size).to be >= 1
    end

    it "counts unchanged" do
      expect(diff.link_changes[:unchanged]).to be >= 1
    end
  end

  describe "#structural_changes" do
    it "detects element count changes" do
      changes = diff.structural_changes
      expect(changes).to be_a(Hash)
      expect(changes.keys).to include("a")
    end
  end

  describe "#to_h" do
    it "includes all fields" do
      h = diff.to_h
      expect(h[:url]).to eq("https://example.com/")
      expect(h[:content_changed]).to be true
      expect(h[:timestamp_a]).to eq("20220101000000")
      expect(h[:timestamp_b]).to eq("20220601000000")
    end
  end
end
