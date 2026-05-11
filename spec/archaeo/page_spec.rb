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

    it "exposes size" do
      expect(subject.size).to eq(18)
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

  describe "#css?" do
    it "returns true for text/css" do
      page = described_class.new(
        content: "body {}", content_type: "text/css",
        status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
      )
      expect(page).to be_css
    end

    it "returns false for text/html" do
      page = described_class.new(
        content: "<html>", content_type: "text/html",
        status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
      )
      expect(page).not_to be_css
    end
  end

  describe "#title" do
    it "extracts the page title" do
      page = described_class.new(
        content: "<html><head><title>My Page</title></head>" \
                 "<body></body></html>",
        content_type: "text/html", status_code: 200,
        archive_url: "u", original_url: "u", timestamp: ts
      )
      expect(page.title).to eq("My Page")
    end
  end

  describe "#to_h" do
    it "returns a hash with all fields" do
      page = described_class.new(
        content: "hello", content_type: "text/html",
        status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
      )
      h = page.to_h
      expect(h[:status_code]).to eq(200)
      expect(h[:size]).to eq(5)
      expect(h[:timestamp]).to be_a(Archaeo::Timestamp)
    end
  end

  describe "#as_json" do
    it "returns a JSON-serializable hash" do
      page = described_class.new(
        content: "hello", content_type: "text/html",
        status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
      )
      h = page.as_json
      expect(h[:timestamp]).to eq("20220615000000")
      expect { JSON.generate(h) }.not_to raise_error
    end
  end

  describe "#inspect" do
    it "shows class, content type and size" do
      page = described_class.new(
        content: "hello", content_type: "text/html",
        status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
      )
      expect(page.inspect).to eq("#<Archaeo::Page text/html 5 bytes>")
    end
  end

  describe "#links" do
    it "extracts links from HTML pages" do
      html = "<html><body>" \
             '<a href="https://example.com/about">About</a>' \
             '<a href="https://other.com/page">External</a>' \
             "</body></html>"
      page = described_class.new(
        content: html, content_type: "text/html", status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/https://example.com/",
        original_url: "https://example.com/", timestamp: ts
      )
      links = page.links
      expect(links.length).to eq(2)
      expect(links[0][:href]).to eq("https://example.com/about")
      expect(links[0][:text]).to eq("About")
      expect(links[0][:external]).to be false
      expect(links[1][:external]).to be true
    end

    it "returns empty array for non-HTML pages" do
      page = described_class.new(
        content: '{"key":"value"}', content_type: "application/json",
        status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
      )
      expect(page.links).to eq([])
    end

    it "resolves relative links against archive URL" do
      html = '<html><body><a href="about">About</a></body></html>'
      page = described_class.new(
        content: html, content_type: "text/html", status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/https://example.com/",
        original_url: "https://example.com/", timestamp: ts
      )
      link = page.links.first
      expect(link[:href]).to eq(
        "https://web.archive.org/web/20220615000000/https://example.com/about",
      )
    end
  end

  describe "#meta_tags" do
    it "extracts meta tags from HTML pages" do
      html = "<html><head>" \
             '<meta name="description" content="A test page">' \
             '<meta property="og:title" content="Test">' \
             '<link rel="canonical" href="https://example.com/">' \
             "</head><body></body></html>"
      page = described_class.new(
        content: html, content_type: "text/html", status_code: 200,
        archive_url: "u", original_url: "u", timestamp: ts
      )
      meta = page.meta_tags
      expect(meta["description"]).to eq("A test page")
      expect(meta["og:title"]).to eq("Test")
      expect(meta["canonical"]).to eq("https://example.com/")
    end

    it "returns empty hash for non-HTML pages" do
      page = described_class.new(
        content: "body {}", content_type: "text/css",
        status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
      )
      expect(page.meta_tags).to eq({})
    end
  end
end
