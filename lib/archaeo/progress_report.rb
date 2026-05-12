# frozen_string_literal: true

module Archaeo
  # Value object representing download progress at a point in time.
  #
  # Provides computed metrics like percentage, speed, and ETA
  # based on current counters and elapsed time.
  ProgressReport = Struct.new(
    :current, :total, :downloaded_bytes, :elapsed, :current_url,
    keyword_init: true
  ) do
    def percent_complete
      return 0.0 if total.nil? || total.zero?

      (current.to_f / total * 100).round(1)
    end

    def speed
      return 0.0 if elapsed.nil? || elapsed.zero?

      downloaded_bytes.to_f / elapsed
    end

    def eta
      return nil if elapsed.nil? || elapsed.zero?
      return nil if total.nil? || current.nil? || current.zero?

      rate = current.to_f / elapsed
      remaining = total - current
      remaining / rate
    end

    def to_h
      {
        current: current,
        total: total,
        percent_complete: percent_complete,
        downloaded_bytes: downloaded_bytes,
        speed: speed,
        eta: eta,
        current_url: current_url,
        elapsed: elapsed,
      }
    end

    def as_json(*)
      to_h.transform_values { |v| v.is_a?(Float) ? v.round(2) : v }
    end
  end
end
