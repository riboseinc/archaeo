# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::UrlRewriter do
  subject(:rewriter) do
    described_class.new(
      "https://web.archive.org/web/20220615000000/",
      "local",
    )
  end

  describe "#rewrite" do
    it "rewrites archive URLs to local paths" do
      url = "https://web.archive.org/web/20220615000000/" \
            "https://example.com/style.css"
      expect(rewriter.rewrite(url))
        .to eq("local/https://example.com/style.css")
    end

    it "leaves non-archive URLs unchanged" do
      expect(rewriter.rewrite("https://cdn.example.com/style.css"))
        .to eq("https://cdn.example.com/style.css")
    end

    it "rewrites URLs with nested paths" do
      url = "https://web.archive.org/web/20220615000000/" \
            "https://example.com/assets/img/logo.png"
      expect(rewriter.rewrite(url))
        .to eq("local/https://example.com/assets/img/logo.png")
    end
  end

  describe "#rewrite_batch" do
    it "rewrites multiple URLs" do
      urls = [
        "https://web.archive.org/web/20220615000000/style.css",
        "https://cdn.example.com/external.css",
      ]
      result = rewriter.rewrite_batch(urls)
      expect(result[0]).to eq("local/style.css")
      expect(result[1]).to eq("https://cdn.example.com/external.css")
    end
  end

  describe "#rewrite_html" do
    it "rewrites src attributes in HTML" do
      html = '<img src="https://web.archive.org/web/20220615000000/logo.png">'
      result = rewriter.rewrite_html(html)
      expect(result).to include('src="local/logo.png"')
      expect(result).not_to include("web.archive.org")
    end

    it "leaves non-archive URLs in HTML unchanged" do
      html = '<img src="https://cdn.example.com/logo.png">'
      result = rewriter.rewrite_html(html)
      expect(result).to include("cdn.example.com")
    end

    it "rewrites srcset attributes" do
      html = '<img srcset="' \
             "https://web.archive.org/web/20220615000000/small.png 300w, " \
             'https://web.archive.org/web/20220615000000/large.png 600w">'
      result = rewriter.rewrite_html(html)
      expect(result).to include("local/small.png 300w")
      expect(result).to include("local/large.png 600w")
    end
  end
end
