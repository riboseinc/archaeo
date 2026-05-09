# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::Page do
  let(:ts) { Archaeo::Timestamp.new(year: 2022, month: 6, day: 15) }

  describe "basic attributes" do
    subject do
      described_class.new(
        content: "<html>Hello</html>",
        content_type: "text/html",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/" \
                     "https://example.com/",
        original_url: "https://example.com/",
        timestamp: ts,
      )
    end

    it "exposes content" do
      expect(subject.content).to eq("<html>Hello</html>")
    end

    it "exposes content_type" do
      expect(subject.content_type).to eq("text/html")
    end

    it "exposes status_code" do
      expect(subject.status_code).to eq(200)
    end

    it "exposes archive_url" do
      expect(subject.archive_url).to include("web.archive.org")
    end

    it "exposes original_url" do
      expect(subject.original_url).to eq("https://example.com/")
    end

    it "exposes timestamp as a Timestamp" do
      expect(subject.timestamp).to be_a(Archaeo::Timestamp)
      expect(subject.timestamp).to eq(ts)
    end

    it "coerces string timestamps" do
      page = described_class.new(
        content: "",
        content_type: "text/plain",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220101000000/" \
                     "https://example.com/",
        original_url: "https://example.com/",
        timestamp: "20220101000000",
      )
      expect(page.timestamp).to be_a(Archaeo::Timestamp)
    end
  end

  describe "encoding handling" do
    it "returns UTF-8 content when already UTF-8 and valid" do
      page = described_class.new(
        content: "Hello UTF-8",
        content_type: "text/html; charset=utf-8",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/" \
                     "https://example.com/",
        original_url: "https://example.com/",
        timestamp: ts,
      )
      expect(page.content).to eq("Hello UTF-8")
      expect(page.content.encoding).to eq(Encoding::UTF_8)
    end

    it "transcodes from ISO-8859-1 to UTF-8 using charset" do
      raw = "\xE4\xF6\xFC".b # äöü in ISO-8859-1
      page = described_class.new(
        content: raw,
        content_type: "text/html; charset=iso-8859-1",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/" \
                     "https://example.com/",
        original_url: "https://example.com/",
        timestamp: ts,
      )
      expect(page.content).to eq("äöü")
      expect(page.content.encoding).to eq(Encoding::UTF_8)
    end

    it "detects charset from HTML meta tag" do
      html = '<html><head><meta charset="utf-8"></head>' \
             "<body>Hello</body></html>"
      page = described_class.new(
        content: html,
        content_type: "text/html",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/" \
                     "https://example.com/",
        original_url: "https://example.com/",
        timestamp: ts,
      )
      expect(page.encoding).to eq(Encoding::UTF_8)
    end

    it "defaults to UTF-8 when no charset is specified" do
      page = described_class.new(
        content: "plain text",
        content_type: "text/html",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/" \
                     "https://example.com/",
        original_url: "https://example.com/",
        timestamp: ts,
      )
      expect(page.encoding).to eq(Encoding::UTF_8)
    end

    it "replaces invalid bytes with ?" do
      raw = "Hello\xFFWorld".b
      page = described_class.new(
        content: raw,
        content_type: "text/html; charset=utf-8",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/" \
                     "https://example.com/",
        original_url: "https://example.com/",
        timestamp: ts,
      )
      expect(page.content).to include("Hello")
      expect(page.content).to include("World")
    end

    it "handles empty content" do
      page = described_class.new(
        content: "",
        content_type: "text/html",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/" \
                     "https://example.com/",
        original_url: "https://example.com/",
        timestamp: ts,
      )
      expect(page.content).to eq("")
    end
  end
end
