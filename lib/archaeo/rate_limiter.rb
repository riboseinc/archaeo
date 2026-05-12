# frozen_string_literal: true

module Archaeo
  # Thread-safe request rate limiter.
  #
  # Enforces a minimum interval between requests to avoid hitting
  # Wayback Machine rate limits. Supports per-host limiting and
  # adaptive backoff when 429 responses are received.
  class RateLimiter
    DEFAULT_MIN_INTERVAL = 0

    def initialize(min_interval: DEFAULT_MIN_INTERVAL)
      @min_interval = min_interval.to_f
      @mutex = Mutex.new
      @last_request_at = 0.0
      @host_last = {}
    end

    def wait(host: nil)
      return if @min_interval <= 0

      @mutex.synchronize do
        if host
          wait_for_host(host)
        else
          wait_global
        end
      end
    end

    def backoff(host: nil)
      @mutex.synchronize do
        if host
          key = host.to_sym
          current = @host_last[key] || @min_interval
          @host_last[key] = [current * 2, 60].min
        else
          @min_interval = [(@min_interval * 2).clamp(0, 60), 60].min
        end
      end
      wait(host: host)
    end

    def reset(host: nil)
      @mutex.synchronize do
        if host
          @host_last.delete(host.to_sym)
        else
          @last_request_at = 0.0
          @host_last.clear
        end
      end
    end

    def interval
      @mutex.synchronize { @min_interval }
    end

    private

    def wait_global
      elapsed = now - @last_request_at
      sleep_for(@min_interval - elapsed) if elapsed < @min_interval
      @last_request_at = now
    end

    def wait_for_host(host)
      key = host.to_sym
      @host_last[key] ||= 0.0
      host_interval = [@min_interval, 0].max
      elapsed = now - @host_last[key]
      sleep_for(host_interval - elapsed) if elapsed < host_interval
      @host_last[key] = now
    end

    def sleep_for(seconds)
      return unless seconds.positive?

      sleep(seconds)
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
