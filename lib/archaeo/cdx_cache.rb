# frozen_string_literal: true

require "json"
require "digest"

module Archaeo
  # Persists CDX API query results to disk for resume support.
  #
  # Caches snapshot lists keyed by query parameters so that
  # interrupted downloads can resume without re-querying CDX.
  class CdxCache
    CACHE_DIR = ".cache"

    def initialize(base_dir)
      @base_dir = base_dir
      @cache_dir = File.join(base_dir, CACHE_DIR)
    end

    def fetch(url, **options)
      key = cache_key(url, options)
      path = cache_path(key)

      if File.exist?(path)
        load_cache(path)
      else
        snapshots = yield
        save_cache(path, url, options, snapshots)
        snapshots
      end
    end

    def cached?(url, **options)
      File.exist?(cache_path(cache_key(url, options)))
    end

    def cache_key(url, options = {})
      parts = [url.to_s]
      parts << options[:from].to_s if options[:from]
      parts << options[:to].to_s if options[:to]
      parts << options[:match_type].to_s if options[:match_type]
      parts += Array(options[:filters]).map(&:to_s) if options[:filters]
      parts += Array(options[:collapse]).map(&:to_s) if options[:collapse]
      parts << options[:sort].to_s if options[:sort]
      Digest::SHA256.hexdigest(parts.join("|"))[0, 16]
    end

    def clear(url = nil, **options)
      if url
        FileUtils.rm_f(cache_path(cache_key(url, options)))
      else
        FileUtils.rm_rf(@cache_dir)
      end
    end

    private

    def cache_path(key)
      FileUtils.mkdir_p(@cache_dir)
      File.join(@cache_dir, "#{key}.cdx.json")
    end

    def load_cache(path)
      data = JSON.parse(File.read(path))
      data["snapshots"].map { |row| build_snapshot(row) }
    end

    def save_cache(path, url, options, snapshots)
      data = {
        "url" => url.to_s,
        "options" => serialize_options(options),
        "cached_at" => Time.now.utc.iso8601,
        "snapshots" => snapshots.map(&:as_json),
      }
      tmp_path = "#{path}.tmp"
      File.write(tmp_path, JSON.generate(data))
      File.rename(tmp_path, path)
    end

    def serialize_options(options)
      h = {}
      h["from"] = options[:from].to_s if options[:from]
      h["to"] = options[:to].to_s if options[:to]
      h["match_type"] = options[:match_type].to_s if options[:match_type]
      h["filters"] = Array(options[:filters]).map(&:to_s) if options[:filters]
      if options[:collapse]
        h["collapse"] =
          Array(options[:collapse]).map(&:to_s)
      end
      h["sort"] = options[:sort].to_s if options[:sort]
      h
    end

    def build_snapshot(row)
      Snapshot.new(
        urlkey: row["urlkey"],
        timestamp: row["timestamp"],
        original_url: row["original_url"],
        mimetype: row["mimetype"],
        status_code: row["status_code"],
        digest: row["digest"],
        length: row["length"],
      )
    end
  end
end
