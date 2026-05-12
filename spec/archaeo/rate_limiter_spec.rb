# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::RateLimiter do
  describe "with zero interval" do
    let(:limiter) { described_class.new(min_interval: 0) }

    it "returns immediately" do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      limiter.wait
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be < 0.1
    end
  end

  describe "with min interval" do
    let(:limiter) { described_class.new(min_interval: 0.05) }

    it "enforces minimum interval between calls" do
      limiter.wait
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      limiter.wait
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be >= 0.04
    end

    it "enforces per-host rate limiting" do
      limiter.wait(host: "a.com")
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      limiter.wait(host: "a.com")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be >= 0.04
    end

    it "allows different hosts without waiting" do
      limiter.wait(host: "a.com")
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      limiter.wait(host: "b.com")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be < 0.1
    end
  end

  describe "#backoff" do
    let(:limiter) { described_class.new(min_interval: 0.01) }

    it "increases interval on backoff" do
      limiter.wait
      limiter.backoff
      expect(limiter.interval).to be > 0.01
    end
  end

  describe "#reset" do
    let(:limiter) { described_class.new(min_interval: 0.05) }

    it "resets host tracking" do
      limiter.wait(host: "a.com")
      limiter.reset(host: "a.com")
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      limiter.wait(host: "a.com")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be < 0.1
    end
  end
end
