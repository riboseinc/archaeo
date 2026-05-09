# frozen_string_literal: true

module Archaeo
  # Tracks download progress for resume support.
  #
  # Persists completed snapshot timestamps to a state file within
  # the output directory, allowing interrupted downloads to resume
  # without re-fetching already downloaded snapshots.
  class DownloadState
    STATE_FILE = ".archaeo-state"

    attr_reader :output_dir

    def initialize(output_dir)
      @output_dir = output_dir
      @path = File.join(output_dir, STATE_FILE)
    end

    def completed?(timestamp)
      timestamps.include?(timestamp.to_s)
    end

    def mark_completed(timestamp)
      timestamps << timestamp.to_s
      save
    end

    def clear
      @timestamps = []
      FileUtils.rm_f(@path)
    end

    private

    def timestamps
      @timestamps ||= load_timestamps
    end

    def load_timestamps
      return [] unless File.exist?(@path)

      File.readlines(@path, chomp: true).reject(&:empty?)
    end

    def save
      File.write(@path, "#{timestamps.uniq.sort.join("\n")}\n")
    end
  end
end
