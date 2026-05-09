# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Archaeo::DownloadState do
  let(:tmpdir) { Dir.mktmpdir }
  let(:state) { described_class.new(tmpdir) }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#completed?" do
    it "returns false for unmarked timestamps" do
      ts = Archaeo::Timestamp.new(year: 2022, month: 6, day: 15)
      expect(state.completed?(ts)).to be false
    end

    it "returns true after marking" do
      ts = Archaeo::Timestamp.new(year: 2022, month: 6, day: 15)
      state.mark_completed(ts)
      expect(state.completed?(ts)).to be true
    end

    it "accepts string timestamps" do
      state.mark_completed("20220615120000")
      expect(state.completed?("20220615120000")).to be true
    end
  end

  describe "#mark_completed" do
    it "persists state to file" do
      ts = Archaeo::Timestamp.new(year: 2022, month: 6, day: 15)
      state.mark_completed(ts)

      state2 = described_class.new(tmpdir)
      expect(state2.completed?(ts)).to be true
    end

    it "deduplicates timestamps" do
      ts = Archaeo::Timestamp.new(year: 2022, month: 6, day: 15)
      state.mark_completed(ts)
      state.mark_completed(ts)

      described_class.new(tmpdir)
      path = File.join(tmpdir, described_class::STATE_FILE)
      lines = File.readlines(path, chomp: true)
      expect(lines.count("20220615000000")).to eq(1)
    end
  end

  describe "#clear" do
    it "removes all tracked timestamps" do
      state.mark_completed(Archaeo::Timestamp.new(year: 2022))
      state.clear

      expect(state.completed?(Archaeo::Timestamp.new(year: 2022)))
        .to be false
    end

    it "deletes the state file" do
      state.mark_completed(Archaeo::Timestamp.new(year: 2022))
      path = File.join(tmpdir, described_class::STATE_FILE)
      expect(File.exist?(path)).to be true

      state.clear
      expect(File.exist?(path)).to be false
    end
  end
end
