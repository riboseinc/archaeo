# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::AssetExtractor do
  describe "#extract" do
    it "extracts CSS stylesheet links" do
      html = '<html><head><link rel="stylesheet" href="/style.css">' \
             "</head><body></body></html>"
      list = described_class.new(html).extract
      expect(list.css).to include("/style.css")
    end

    it "extracts JavaScript sources" do
      html = '<html><body><script src="/app.js"></script></body></html>'
      list = described_class.new(html).extract
      expect(list.js).to include("/app.js")
    end

    it "extracts image sources" do
      html = '<html><body><img src="/logo.png" alt="Logo"></body></html>'
      list = described_class.new(html).extract
      expect(list.images).to include("/logo.png")
    end

    it "extracts preloaded fonts" do
      html = '<html><head><link rel="preload" as="font" ' \
             'href="/font.woff2"></head></html>'
      list = described_class.new(html).extract
      expect(list.fonts).to include("/font.woff2")
    end

    it "extracts media sources" do
      html = '<html><body><video src="/video.mp4"></video></body></html>'
      list = described_class.new(html).extract
      expect(list.media).to include("/video.mp4")
    end

    it "extracts source elements" do
      html = '<html><body><source src="/audio.mp3"></body></html>'
      list = described_class.new(html).extract
      expect(list.media).to include("/audio.mp3")
    end

    it "resolves relative URLs against base_url" do
      html = '<html><head><link rel="stylesheet" href="css/style.css">' \
             "</head></html>"
      list = described_class.new(html,
                                 base_url: "https://example.com/").extract
      expect(list.css).to include("https://example.com/css/style.css")
    end

    it "does not resolve data URIs" do
      html = '<html><body><img src="data:image/png;base64,abc123">' \
             "</body></html>"
      list = described_class.new(html).extract
      expect(list.images).to eq(["data:image/png;base64,abc123"])
    end

    it "does not resolve fragment-only URLs" do
      html = '<html><body><img src="#section"></body></html>'
      list = described_class.new(html).extract
      expect(list.images).to eq(["#section"])
    end

    it "does not resolve protocol-relative URLs" do
      html = '<html><head><link rel="stylesheet" href="//cdn.example.com/style.css">' \
             "</head></html>"
      list = described_class.new(html,
                                 base_url: "https://example.com/").extract
      expect(list.css).to eq(["//cdn.example.com/style.css"])
    end

    it "extracts URLs from inline CSS url()" do
      html = "<html><head><style>" \
             '@font-face { src: url("/fonts/myfont.woff2"); }' \
             "</style></head></html>"
      list = described_class.new(html).extract
      expect(list.fonts).to include("/fonts/myfont.woff2")
    end

    it "extracts multiple asset types from a complex page" do
      html = <<~HTML
        <html>
        <head>
          <link rel="stylesheet" href="/style.css">
          <link rel="preload" as="font" href="/font.woff2">
          <script src="/app.js"></script>
        </head>
        <body>
          <img src="/logo.png">
          <video src="/intro.mp4"></video>
        </body>
        </html>
      HTML
      list = described_class.new(html).extract
      expect(list.css).to include("/style.css")
      expect(list.js).to include("/app.js")
      expect(list.images).to include("/logo.png")
      expect(list.fonts).to include("/font.woff2")
      expect(list.media).to include("/intro.mp4")
    end
  end

  describe "favicon extraction" do
    it "extracts link rel=icon" do
      html = '<html><head><link rel="icon" href="/favicon.ico">' \
             "</head></html>"
      list = described_class.new(html).extract
      expect(list.images).to include("/favicon.ico")
    end

    it "extracts link rel=shortcut icon" do
      html = '<html><head><link rel="shortcut icon" ' \
             'href="/favicon.png"></head></html>'
      list = described_class.new(html).extract
      expect(list.images).to include("/favicon.png")
    end
  end
end
