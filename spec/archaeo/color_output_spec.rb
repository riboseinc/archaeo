# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::ColorOutput do
  describe "with color enabled" do
    let(:color) { described_class.new(enabled: true) }

    it "wraps text in red escape codes" do
      expect(color.red("error")).to eq("\e[31merror\e[0m")
    end

    it "wraps text in green escape codes" do
      expect(color.green("ok")).to eq("\e[32mok\e[0m")
    end

    it "wraps text in yellow escape codes" do
      expect(color.yellow("warn")).to eq("\e[33mwarn\e[0m")
    end

    it "wraps text in cyan escape codes" do
      expect(color.cyan("info")).to eq("\e[36minfo\e[0m")
    end

    it "applies bold style" do
      expect(color.bold("strong")).to eq("\e[1mstrong\e[0m")
    end

    it "combines success with green+bold" do
      result = color.success("done")
      expect(result).to include("\e[32m")
      expect(result).to include("\e[1m")
    end

    it "combines error with red+bold" do
      result = color.error("fail")
      expect(result).to include("\e[31m")
      expect(result).to include("\e[1m")
    end

    it "combines warning with yellow+bold" do
      result = color.warning("careful")
      expect(result).to include("\e[33m")
      expect(result).to include("\e[1m")
    end
  end

  describe "with color disabled" do
    let(:color) { described_class.new(enabled: false) }

    it "returns plain text without escape codes" do
      expect(color.red("error")).to eq("error")
    end

    it "success returns plain text" do
      expect(color.success("done")).to eq("done")
    end
  end

  describe "auto-detection" do
    it "respects NO_COLOR env var" do
      with_env("NO_COLOR" => "1") do
        color = described_class.new(stream: $stderr)
        expect(color.red("test")).to eq("test")
      end
    end

    it "respects TERM=dumb" do
      with_env("TERM" => "dumb") do
        color = described_class.new(stream: $stderr)
        expect(color.red("test")).to eq("test")
      end
    end
  end
end
