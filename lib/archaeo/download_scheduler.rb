# frozen_string_literal: true

module Archaeo
  # Schedules and orders snapshot downloads by strategy and priority.
  #
  # Supports multiple ordering strategies (newest_first, oldest_first,
  # breadth_first, depth_first) and priority rules (html_first,
  # smallest_first, largest_first) for intelligent download ordering.
  class DownloadScheduler
    STRATEGIES = %i[newest_first oldest_first breadth_first depth_first].freeze
    PRIORITIES = %i[html_first smallest_first largest_first].freeze

    def initialize(strategy: :newest_first, priority: nil,
                   max_file_size: nil, min_file_size: nil)
      validate_strategy(strategy)
      validate_priority(priority) if priority

      @strategy = strategy
      @priority = priority
      @max_file_size = max_file_size
      @min_file_size = min_file_size
    end

    def schedule(snapshots)
      filtered = apply_size_filters(snapshots)
      ordered = apply_strategy(filtered)
      apply_priority(ordered)
    end

    private

    def validate_strategy(strategy)
      return if STRATEGIES.include?(strategy.to_sym)

      raise ArgumentError,
            "Invalid strategy: #{strategy}. Use: #{STRATEGIES.join(', ')}"
    end

    def validate_priority(priority)
      return if PRIORITIES.include?(priority.to_sym)

      raise ArgumentError,
            "Invalid priority: #{priority}. Use: #{PRIORITIES.join(', ')}"
    end

    def apply_size_filters(snapshots)
      result = snapshots
      if @max_file_size
        result = result.reject { |s| s.length && s.length > @max_file_size }
      end
      if @min_file_size
        result = result.reject { |s| s.length && s.length < @min_file_size }
      end
      result
    end

    def apply_strategy(snapshots)
      case @strategy.to_sym
      when :newest_first
        snapshots.sort_by { |s| -s.timestamp.to_i }
      when :oldest_first
        snapshots.sort_by(&:timestamp)
      when :breadth_first
        sort_by_depth(snapshots, depth: :shallow)
      when :depth_first
        sort_by_depth(snapshots, depth: :deep)
      end
    end

    def apply_priority(snapshots)
      return snapshots unless @priority

      case @priority.to_sym
      when :html_first
        html, rest = snapshots.partition { |s| html?(s) }
        html + rest
      when :smallest_first
        snapshots.sort_by { |s| s.length || 0 }
      when :largest_first
        snapshots.sort_by { |s| -(s.length || 0) }
      end
    end

    def sort_by_depth(snapshots, depth:)
      segments = snapshots.map do |snap|
        path = snap.original_url.to_s
        depth_count = path.count("/")
        [snap, depth_count]
      end

      if depth == :shallow
        segments.sort_by { |_, d| d }.map(&:first)
      else
        segments.sort_by { |_, d| -d }.map(&:first)
      end
    end

    def html?(snapshot)
      snapshot.mimetype.to_s.include?("text/html")
    end
  end
end
