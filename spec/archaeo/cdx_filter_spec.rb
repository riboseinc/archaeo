# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::CdxFilter do
  describe "#initialize" do
    it "accepts a valid filter expression" do
      filter = described_class.new("statuscode:200")
      expect(filter.to_s).to eq("statuscode:200")
    end

    it "accepts a negated filter expression" do
      filter = described_class.new("!statuscode:200")
      expect(filter.to_s).to eq("!statuscode:200")
    end

    it "accepts a filter with regex pattern" do
      filter = described_class.new("mimetype:text/.*")
      expect(filter.to_s).to eq("mimetype:text/.*")
    end

    it "raises ArgumentError for invalid field" do
      expect { described_class.new("invalid_field:value") }
        .to raise_error(ArgumentError, /Invalid CDX filter field/)
    end
  end

  describe "#to_s" do
    it "returns the filter expression" do
      filter = described_class.new("mimetype:text/html")
      expect(filter.to_s).to eq("mimetype:text/html")
    end
  end

  describe "#negated?" do
    it "returns true when expression starts with !" do
      expect(described_class.new("!statuscode:200")).to be_negated
    end

    it "returns false for normal expressions" do
      expect(described_class.new("statuscode:200")).not_to be_negated
    end
  end

  describe "#field" do
    it "extracts the field name" do
      expect(described_class.new("statuscode:200").field)
        .to eq("statuscode")
    end

    it "extracts the field name from negated expressions" do
      expect(described_class.new("!statuscode:200").field)
        .to eq("statuscode")
    end
  end

  describe ".by_status" do
    it "builds a status code filter" do
      expect(described_class.by_status(200).to_s).to eq("statuscode:200")
    end
  end

  describe ".excluding_status" do
    it "builds a negated status code filter" do
      filter = described_class.excluding_status(404)
      expect(filter.to_s).to eq("!statuscode:404")
      expect(filter).to be_negated
    end
  end

  describe ".by_mimetype" do
    it "builds a mimetype filter" do
      expect(described_class.by_mimetype("text/html").to_s)
        .to eq("mimetype:text/html")
    end
  end

  describe ".excluding_mimetype" do
    it "builds a negated mimetype filter" do
      expect(described_class.excluding_mimetype("text/html").to_s)
        .to eq("!mimetype:text/html")
    end
  end

  describe ".by_digest" do
    it "builds a digest filter" do
      expect(described_class.by_digest("SHA1-abc").to_s)
        .to eq("digest:SHA1-abc")
    end
  end

  describe ".by_url" do
    it "builds an original URL filter" do
      expect(described_class.by_url("example.com").to_s)
        .to eq("original:example.com")
    end
  end

  describe ".by_urlkey" do
    it "builds a urlkey filter" do
      expect(described_class.by_urlkey("com,example").to_s)
        .to eq("urlkey:com,example")
    end
  end

  describe "valid fields" do
    Archaeo::CdxFilter::VALID_FIELDS.each do |field|
      it "accepts #{field}" do
        expect { described_class.new("#{field}:value") }.not_to raise_error
      end
    end
  end

  describe ".only_html" do
    it "returns a filter for text/html" do
      filters = described_class.only_html
      expect(filters.first.to_s).to eq("mimetype:text/html")
    end
  end

  describe ".by_mimetype_prefix" do
    it "builds a mimetype filter with wildcard" do
      expect(described_class.by_mimetype_prefix("image/").to_s)
        .to eq("mimetype:image/.*")
    end
  end

  describe ".excluding_redirects" do
    it "returns filters for 3xx status codes" do
      filters = described_class.excluding_redirects
      expect(filters.size).to eq(5)
      expect(filters.map(&:to_s)).to all(start_with("!statuscode:"))
    end
  end
end
