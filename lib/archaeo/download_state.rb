# frozen_string_literal: true

require "set"

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
      timestamps_set.include?(timestamp.to_s)
    end

    def mark_completed(timestamp)
      ts = timestamp.to_s
      return if timestamps_set.include?(ts)

      timestamps << ts
      @timestamps_set = nil
      save
    end

    def clear
      @timestamps = []
      @timestamps_set = nil
      FileUtils.rm_f(@path)
    end

    private

    def timestamps
      @timestamps ||= load_timestamps
    end

    def timestamps_set
      @timestamps_set ||= timestamps.to_set
    end

    def load_timestamps
      return [] unless File.exist?(@path)

      File.readlines(@path, chomp: true).reject(&:empty?)
    end

    def save
      content = "#{timestamps.sort.join("\n")}\n"
      tmp_path = "#{@path}.tmp"
      File.write(tmp_path, content)
      File.rename(tmp_path, @path)
    end
  end
end
