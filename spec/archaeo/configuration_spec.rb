# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::Configuration do
  let(:tmpdir) { Dir.mktmpdir }
  let(:config_path) { File.join(tmpdir, ".archaeo.yml") }

  after { FileUtils.rm_rf(tmpdir) }

  describe "loading config" do
    it "loads defaults when no file exists" do
      config = described_class.new(path: config_path)
      expect(config.get("output_dir")).to eq("archive")
    end

    it "loads values from config file" do
      File.write(config_path, { "defaults" => { "rate_limit" => 0.5 } }.to_yaml)
      config = described_class.new(path: config_path)
      expect(config.get("rate_limit")).to eq(0.5)
    end

    it "loads profile-specific values" do
      data = { "profiles" => { "fast" => { "concurrency" => 8 } } }.to_yaml
      File.write(config_path, data)
      config = described_class.new(path: config_path)
      expect(config.get("concurrency", profile: "fast")).to eq(8)
    end

    it "handles malformed YAML gracefully" do
      File.write(config_path, "  invalid: yaml: [")
      config = described_class.new(path: config_path)
      expect(config.get("output_dir")).to eq("archive")
    end
  end

  describe "#set" do
    it "persists values to file" do
      config = described_class.new(path: config_path)
      config.set("rate_limit", 1.0)
      config2 = described_class.new(path: config_path)
      expect(config2.get("rate_limit")).to eq(1.0)
    end

    it "persists profile values" do
      config = described_class.new(path: config_path)
      config.set("concurrency", 4, profile: "fast")
      expect(config.get("concurrency", profile: "fast")).to eq(4)
    end
  end

  describe "#profiles" do
    it "lists available profiles" do
      data = { "profiles" => { "fast" => {}, "careful" => {} } }.to_yaml
      File.write(config_path, data)
      config = described_class.new(path: config_path)
      expect(config.profiles).to contain_exactly("fast", "careful")
    end
  end

  describe "#to_h" do
    it "returns config as hash" do
      config = described_class.new(path: config_path)
      h = config.to_h
      expect(h).to be_a(Hash)
      expect(h[:defaults]).to be_a(Hash)
      expect(h[:profiles]).to be_a(Hash)
    end
  end
end
