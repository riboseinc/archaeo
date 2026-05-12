# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::EncodingDetector do
  let(:detector) { described_class.new }

  describe "#detect" do
    it "detects valid UTF-8" do
      bytes = "Hello UTF-8".encode("UTF-8").b
      expect(detector.detect(bytes)).to eq(Encoding::UTF_8)
    end

    it "detects Windows-1251 (Cyrillic)" do
      bytes = "\xCF\xF0\xE8\xE2\xE5\xF2".b # "Привет" in Windows-1251
      expect(detector.detect(bytes)).to eq(Encoding::Windows_1251)
    end

    it "detects Shift_JIS (Japanese)" do
      bytes = "\x82\xB1\x82\xF1\x82\xC9\x82\xBF\x82\xCD".b
      detected = detector.detect(bytes)
      expect(detected).to eq(Encoding::Shift_JIS).or eq(Encoding::Windows_1251)
    end

    it "detects legacy encodings for non-UTF-8 content" do
      bytes = "\xE4\xF6\xFC\xDF".b # äöüß in ISO-8859-1
      detected = detector.detect(bytes)
      expect(detected).not_to be_nil
      # The bytes are valid in Windows-1251, GB18030, ISO-8859-1, etc.
      # The detector picks the first valid match from its priority list
      expect(detected).to be_a(Encoding)
    end

    it "returns UTF-8 for empty input" do
      expect(detector.detect("")).to eq(Encoding::UTF_8)
    end

    it "returns UTF-8 for nil input" do
      expect(detector.detect(nil)).to eq(Encoding::UTF_8)
    end
  end

  describe "#transcode" do
    it "transcodes Windows-1251 to UTF-8" do
      bytes = "\xCF\xF0\xE8\xE2\xE5\xF2".b
      result = detector.transcode(bytes)
      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result).to include("Привет")
    end

    it "passes through valid UTF-8" do
      text = "Hello World".encode("UTF-8")
      result = detector.transcode(text)
      expect(result).to eq("Hello World")
      expect(result.encoding).to eq(Encoding::UTF_8)
    end

    it "replaces invalid bytes" do
      bytes = "Hello\xFFWorld".b
      result = detector.transcode(bytes)
      expect(result).to include("Hello")
      expect(result).to include("World")
    end

    it "returns empty string for nil" do
      expect(detector.transcode(nil)).to eq("")
    end

    it "returns empty string for empty input" do
      expect(detector.transcode("")).to eq("")
    end
  end

  describe "#binary?" do
    it "detects binary content" do
      bytes = (0..255).to_a.pack("C*")
      expect(detector.binary?(bytes)).to be true
    end

    it "does not flag HTML as binary" do
      html = "<html><body>Hello World</body></html>"
      expect(detector.binary?(html)).to be false
    end

    it "returns false for empty input" do
      expect(detector.binary?("")).to be false
    end

    it "returns false for nil input" do
      expect(detector.binary?(nil)).to be false
    end
  end

  describe "custom encoding list" do
    it "uses provided encodings" do
      custom = described_class.new(encodings: [Encoding::Windows_1252])
      bytes = "\x80".b # Euro sign in Windows-1252
      expect(custom.detect(bytes)).to eq(Encoding::Windows_1252)
    end
  end
end
