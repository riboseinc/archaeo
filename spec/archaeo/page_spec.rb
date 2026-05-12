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

  describe "content extraction" do
    let(:complex_html) do
      <<~HTML
        <html><head><title>Test</title></head>
        <body>
          <h1>Main Title</h1>
          <h2>Subtitle</h2>
          <img src="photo.jpg" alt="A photo" width="800" height="600">
          <img src="icon.png">
          <form action="/submit" method="POST">
            <input type="text" name="q">
            <input type="hidden" name="csrf" value="abc">
            <select name="color"><option>red</option></select>
          </form>
          <script src="app.js" type="text/javascript"></script>
          <script>console.log('inline')</script>
        </body></html>
      HTML
    end

    let(:html_page) do
      described_class.new(
        content: complex_html, content_type: "text/html",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615/https://example.com/",
        original_url: "https://example.com/", timestamp: ts
      )
    end

    describe "#headings" do
      it "extracts headings with levels" do
        h = html_page.headings
        expect(h.size).to eq(2)
        expect(h[0]).to eq({ level: 1, text: "Main Title" })
        expect(h[1]).to eq({ level: 2, text: "Subtitle" })
      end

      it "returns empty array for non-HTML" do
        page = described_class.new(
          content: "body", content_type: "text/plain",
          status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
        )
        expect(page.headings).to eq([])
      end
    end

    describe "#images" do
      it "extracts images with attributes" do
        imgs = html_page.images
        expect(imgs.size).to eq(2)
        expect(imgs[0][:src]).to eq("photo.jpg")
        expect(imgs[0][:alt]).to eq("A photo")
        expect(imgs[0][:width]).to eq(800)
      end

      it "returns empty array for non-HTML" do
        page = described_class.new(
          content: "body", content_type: "text/css",
          status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
        )
        expect(page.images).to eq([])
      end
    end

    describe "#forms" do
      it "extracts forms with fields" do
        forms = html_page.forms
        expect(forms.size).to eq(1)
        expect(forms[0][:action]).to eq("/submit")
        expect(forms[0][:method]).to eq("POST")
        field_names = forms[0][:fields].map { |f| f[:name] }
        expect(field_names).to contain_exactly("q", "csrf", "color")
      end

      it "returns empty array for non-HTML" do
        page = described_class.new(
          content: "body", content_type: "text/plain",
          status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
        )
        expect(page.forms).to eq([])
      end
    end

    describe "#scripts" do
      it "extracts script elements" do
        scripts = html_page.scripts
        expect(scripts.size).to eq(2)
        expect(scripts[0][:src]).to eq("app.js")
        expect(scripts[0][:type]).to eq("text/javascript")
        expect(scripts[1][:src]).to eq("")
      end

      it "returns empty array for non-HTML" do
        page = described_class.new(
          content: "body", content_type: "text/plain",
          status_code: 200, archive_url: "u", original_url: "u", timestamp: ts
        )
        expect(page.scripts).to eq([])
      end
    end
  end
end
