# frozen_string_literal: true

require "json"
require "set"

module Archaeo
  # Tracks download progress for resume support.
  #
  # Persists completed snapshot metadata to a JSONL state file within
  # the output directory, allowing interrupted downloads to resume
  # without re-fetching already downloaded snapshots.
  class DownloadState
    STATE_FILE = ".archaeo-state"

    attr_reader :output_dir

    def initialize(output_dir)
      @output_dir = output_dir
      @path = File.join(output_dir, STATE_FILE)
      @mutex = Mutex.new
    end

    def completed?(timestamp)
      @mutex.synchronize { entries_key.include?(timestamp.to_s) }
    end

    def mark_completed(timestamp, url: nil, bytes: nil)
      @mutex.synchronize do
        ts = timestamp.to_s
        return if entries_key.include?(ts)

        entry = { "ts" => ts, "at" => Time.now.utc.iso8601 }
        entry["url"] = url if url
        entry["bytes"] = bytes if bytes
        entries << entry
        @entries_key = nil
        save
      end
    end

    def entry_for(timestamp)
      @mutex.synchronize { entries.find { |e| e["ts"] == timestamp.to_s } }
    end

    def total_bytes
      @mutex.synchronize { entries.sum { |e| e["bytes"].to_i } }
    end

    def size
      @mutex.synchronize { entries.size }
    end

    def timestamps
      @mutex.synchronize { entries.map { |e| e["ts"] } }
    end

    def clear
      @mutex.synchronize do
        @entries = []
        @entries_key = nil
        FileUtils.rm_f(@path)
      end
    end

    private

    def entries
      @entries ||= load_entries
    end

    def entries_key
      @entries_key ||= entries.each_with_object(Set.new) { |e, s| s << e["ts"] }
    end

    def load_entries
      return [] unless File.exist?(@path)

      first_line = File.open(@path, &:readline).strip
      if first_line.start_with?("{")
        parse_jsonl
      else
        migrate_legacy(first_line)
      end
    rescue EOFError
      []
    end

    def parse_jsonl
      File.readlines(@path, chomp: true).reject(&:empty?).map do |line|
        JSON.parse(line)
      end
    end

    def migrate_legacy(_first_line)
      File.readlines(@path, chomp: true).reject(&:empty?).map do |ts|
        { "ts" => ts }
      end
    end

    def save
      content = "#{entries.map { |e| JSON.generate(e) }.join("\n")}\n"
      tmp_path = "#{@path}.tmp"
      File.write(tmp_path, content)
      File.rename(tmp_path, @path)
    end
  end
end
