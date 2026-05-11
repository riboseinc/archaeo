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

      state2 = described_class.new(tmpdir)
      entries = state2.entry_for(ts)
      expect(entries["ts"]).to eq("20220615000000")
    end
  end

  describe "#mark_completed with metadata" do
    it "stores url and bytes" do
      ts = Archaeo::Timestamp.new(year: 2022, month: 6, day: 15)
      state.mark_completed(ts, url: "https://example.com/",
                               bytes: 12345)

      entry = state.entry_for(ts)
      expect(entry["url"]).to eq("https://example.com/")
      expect(entry["bytes"]).to eq(12345)
    end

    it "computes total_bytes" do
      state.mark_completed("20220101000000", bytes: 100)
      state.mark_completed("20220102000000", bytes: 200)

      expect(state.total_bytes).to eq(300)
    end
  end

  describe "legacy format migration" do
    it "reads legacy plain-text state files" do
      path = File.join(tmpdir, described_class::STATE_FILE)
      File.write(path, "20220101000000\n20220102000000\n")

      state2 = described_class.new(tmpdir)
      expect(state2.completed?("20220101000000")).to be true
      expect(state2.completed?("20220102000000")).to be true
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

  describe "#size" do
    it "returns the number of completed entries" do
      state.mark_completed("20220101000000")
      state.mark_completed("20220102000000")
      expect(state.size).to eq(2)
    end
  end

  describe "#timestamps" do
    it "returns an array of timestamp strings" do
      state.mark_completed("20220101000000")
      state.mark_completed("20220102000000")
      expect(state.timestamps).to eq(%w[20220101000000 20220102000000])
    end
  end

  describe "thread safety" do
    it "handles concurrent mark_completed calls" do
      threads = Array.new(10) do |i|
        Thread.new { state.mark_completed(format("202206%02d000000", i + 1)) }
      end
      threads.each(&:join)
      expect(state.size).to eq(10)
    end
  end
end
