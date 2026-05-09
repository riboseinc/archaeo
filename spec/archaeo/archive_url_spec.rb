# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::ArchiveUrl do
  let(:ts) { Archaeo::Timestamp.new(year: 2022, month: 6, day: 15) }

  describe ".new" do
    it "constructs a normal archive URL" do
      url = described_class.new("https://example.com/",
                                timestamp: ts)
      expect(url.to_s).to eq(
        "https://web.archive.org/web/" \
        "20220615000000/https://example.com/",
      )
    end

    it "constructs an identity archive URL" do
      url = described_class.new("https://example.com/",
                                timestamp: ts, identity: true)
      expect(url.to_s).to eq(
        "https://web.archive.org/web/" \
        "20220615000000id_/https://example.com/",
      )
    end

    it "coerces string timestamps" do
      url = described_class.new("https://example.com/",
                                timestamp: "20220101120000")
      expect(url.timestamp).to be_a(Archaeo::Timestamp)
      expect(url.timestamp.to_s).to eq("20220101120000")
    end
  end

  describe ".parse" do
    it "parses a normal archive URL" do
      url = described_class.parse(
        "https://web.archive.org/web/" \
        "20220615000000/https://example.com/",
      )
      expect(url.original_url).to eq("https://example.com/")
      expect(url.timestamp.to_s).to eq("20220615000000")
      expect(url).not_to be_identity
    end

    it "parses an identity archive URL" do
      url = described_class.parse(
        "https://web.archive.org/web/" \
        "20220615000000id_/https://example.com/",
      )
      expect(url.original_url).to eq("https://example.com/")
      expect(url).to be_identity
    end

    it "raises for non-archive URLs" do
      expect { described_class.parse("https://example.com/") }
        .to raise_error(ArgumentError, /Not a valid archive URL/)
    end
  end

  describe "#identity?" do
    it "returns false for normal URLs" do
      url = described_class.new("https://example.com/",
                                timestamp: ts)
      expect(url).not_to be_identity
    end

    it "returns true for identity URLs" do
      url = described_class.new("https://example.com/",
                                timestamp: ts, identity: true)
      expect(url).to be_identity
    end
  end
end
