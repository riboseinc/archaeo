# frozen_string_literal: true

module Archaeo
  # Time-bucketed snapshot frequency analysis.
  #
  # Groups snapshots by configurable time buckets (day, week, month, year)
  # for frequency analysis and coverage reporting.
  class CdxTimeline
    BUCKET_FORMATS = {
      day: "%Y%m%d",
      week: "%YW%V",
      month: "%Y%m",
      year: "%Y",
    }.freeze

    def initialize(snapshots, bucket_size: :month)
      @bucket_size = bucket_size
      @buckets = build_buckets(snapshots)
    end

    def to_a
      @buckets.sort_by(&:first)
    end

    def to_h
      @buckets.dup
    end

    def peak
      @buckets.max_by(&:last)
    end

    def total
      @buckets.values.sum
    end

    def span
      keys = @buckets.keys
      return nil if keys.empty?

      [keys.first, keys.last]
    end

    def empty?
      @buckets.empty?
    end

    def size
      @buckets.size
    end

    def inspect
      "#<#{self.class.name} #{total} snapshots in #{@buckets.size} buckets>"
    end

    private

    def build_buckets(snapshots)
      fmt = BUCKET_FORMATS[@bucket_size] || BUCKET_FORMATS[:month]
      snapshots.each_with_object(Hash.new(0)) do |snap, counts|
        key = snap.timestamp.to_time.strftime(fmt)
        counts[key] += 1
      end
    end
  end
end
