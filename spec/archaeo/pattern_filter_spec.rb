# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::PatternFilter do
  describe "include-only patterns" do
    let(:filter) { described_class.new(only: "/images/") }

    it "matches URLs containing the pattern" do
      expect(filter.match?("https://example.com/images/logo.png")).to be true
    end

    it "rejects URLs not matching the pattern" do
      expect(filter.match?("https://example.com/about.html")).to be false
    end
  end

  describe "exclude patterns" do
    let(:filter) { described_class.new(exclude: "%r{\\.pdf$}") }

    it "rejects URLs matching the exclude pattern" do
      expect(filter.reject?("https://example.com/doc.pdf")).to be true
    end

    it "allows URLs not matching the exclude pattern" do
      expect(filter.reject?("https://example.com/page.html")).to be false
    end
  end

  describe "exclude patterns" do
    let(:filter) { described_class.new(exclude: "%r{\\.pdf$}") }

    it "rejects URLs matching the exclude pattern" do
      expect(filter.match?("https://example.com/doc.pdf")).to be false
    end

    it "allows URLs not matching the exclude pattern" do
      expect(filter.match?("https://example.com/page.html")).to be true
    end
  end

  describe "combined only and exclude" do
    let(:filter) do
      described_class.new(
        only: "/blog/",
        exclude: "%r{/blog/page/\\d+}",
      )
    end

    it "includes matching URLs" do
      expect(filter.match?("https://example.com/blog/post")).to be true
    end

    it "excludes URLs matching the exclude pattern" do
      expect(filter.match?("https://example.com/blog/page/2")).to be false
    end

    it "rejects URLs not matching the only pattern" do
      expect(filter.match?("https://example.com/about")).to be false
    end
  end

  describe "#reject?" do
    let(:filter) { described_class.new(exclude: "%r{\\.pdf$}") }

    it "returns true for excluded URLs" do
      expect(filter.reject?("https://example.com/doc.pdf")).to be true
    end

    it "returns false for allowed URLs" do
      expect(filter.reject?("https://example.com/page.html")).to be false
    end
  end

  describe ".to_regex" do
    it "converts %r{...} strings to Regexp" do
      re = described_class.to_regex("%r{\\.pdf$}")
      expect(re).to be_a(Regexp)
      expect("doc.pdf").to match(re)
    end

    it "converts /.../ strings to Regexp" do
      re = described_class.to_regex("/images/")
      expect(re).to be_a(Regexp)
      expect("/images/logo").to match(re)
    end

    it "handles inline flags" do
      re = described_class.to_regex("/HTML/i")
      expect("html").to match(re)
    end

    it "escapes plain strings as substring match" do
      re = described_class.to_regex("/blog/")
      expect("example.com/blog/post").to match(re)
    end

    it "returns Regexp objects as-is" do
      re = described_class.to_regex(/\.css$/)
      expect(re).to eq(/\.css$/)
    end

    it "raises for invalid types" do
      expect { described_class.to_regex(123) }
        .to raise_error(ArgumentError, /String or Regexp/)
    end
  end

  describe "with no patterns" do
    let(:filter) { described_class.new }

    it "matches all URLs" do
      expect(filter.match?("https://example.com/anything")).to be true
    end
  end
end
