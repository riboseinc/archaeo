# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Archaeo::SubdomainDiscovery do
  let(:discovery) { described_class.new("example.com") }

  describe "#base_domain" do
    it "extracts base domain from subdomain" do
      expect(discovery.base_domain("blog.example.com")).to eq("example.com")
    end

    it "handles multi-part TLDs" do
      d = described_class.new("example.co.uk")
      expect(d.base_domain("blog.example.co.uk")).to eq("example.co.uk")
    end

    it "handles bare domain" do
      expect(discovery.base_domain("example.com")).to eq("example.com")
    end
  end

  describe "#scan_content" do
    it "discovers subdomains from HTML" do
      html = '<a href="https://blog.example.com/post">' \
             '<img src="https://cdn.example.com/img.png"></a>'
      subdomains = discovery.scan_content(html, content_type: :html)
      expect(subdomains).to include("blog.example.com", "cdn.example.com")
    end

    it "discovers subdomains from CSS" do
      css = "body { background: url('https://cdn.example.com/bg.png'); }"
      subdomains = discovery.scan_content(css, content_type: :css)
      expect(subdomains).to include("cdn.example.com")
    end

    it "discovers subdomains from JS" do
      js = "var url = 'https://api.example.com/v1/data';"
      subdomains = discovery.scan_content(js, content_type: :js)
      expect(subdomains).to include("api.example.com")
    end

    it "excludes the base domain itself" do
      html = '<a href="https://example.com/page"></a>'
      subdomains = discovery.scan_content(html, content_type: :html)
      expect(subdomains).not_to include("example.com")
    end

    it "excludes unrelated domains" do
      html = '<a href="https://other.com/page"></a>'
      subdomains = discovery.scan_content(html, content_type: :html)
      expect(subdomains).to be_empty
    end
  end

  describe "#scan_files" do
    let(:tmpdir) { Dir.mktmpdir("archaeo-subdomain-test") }

    after { FileUtils.rm_rf(tmpdir) }

    it "scans HTML files in directory" do
      File.write(File.join(tmpdir, "index.html"),
                 '<a href="https://blog.example.com/post">Link</a>')
      subdomains = discovery.scan_files(tmpdir)
      expect(subdomains).to include("blog.example.com")
    end

    it "ignores binary files" do
      File.binwrite(File.join(tmpdir, "image.png"), "\x89PNG\r\n")
      subdomains = discovery.scan_files(tmpdir)
      expect(subdomains).to be_empty
    end
  end
end
