# frozen_string_literal: true

require "fileutils"

module Archaeo
  DownloadSummary = Struct.new(
    :total, :downloaded, :skipped, :failed, :bytes_written, :elapsed,
    keyword_init: true
  )

  # Downloads all archived snapshots of a URL with resume support.
  #
  # Queries the CDX API for matching snapshots, fetches each page,
  # and saves content to disk. Progress is tracked in a state file
  # for interrupted download recovery.
  class BulkDownloader
    def initialize(client: HttpClient.new, output_dir: "archive",
                   cdx_api: nil, concurrency: 1, on_error: nil,
                   rate_limiter: nil, path_sanitizer: nil)
      @client = client
      @output_dir = output_dir
      @cdx_api = cdx_api
      @concurrency = [1, concurrency.to_i].max
      @on_error = on_error
      @rate_limiter = rate_limiter || RateLimiter.new
      @path_sanitizer = path_sanitizer || PathSanitizer.new
    end

    def download(url, from: nil, to: nil, resume: false,
                 dry_run: false, all_timestamps: false,
                 filter: nil, page_requisites: false,
                 snapshot_at: nil, max_snapshots: nil,
                 strategy: nil, &block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      url = UrlNormalizer.normalize(url)
      FileUtils.mkdir_p(@output_dir) unless dry_run

      snapshots = fetch_snapshots(url, from: from, to: to,
                                       all_timestamps: all_timestamps,
                                       snapshot_at: snapshot_at)
      snapshots = apply_filter(snapshots, filter)
      snapshots = schedule_snapshots(snapshots, strategy)
      snapshots = snapshots.first(max_snapshots) if max_snapshots
      downloaded, skipped, bytes, failed =
        run_download(snapshots, resume, dry_run, page_requisites, block)

      build_summary(start_time, snapshots.size, downloaded,
                    skipped, bytes, failed: failed)
    end

    private

    def fetch_snapshots(url, from:, to:, all_timestamps:, snapshot_at:)
      cdx = @cdx_api || CdxApi.new(client: @client)

      if snapshot_at
        ts = Timestamp.coerce(snapshot_at)
        return cdx.composite_snapshot(url, timestamp: ts, collapse: ["digest"])
      end

      options = {}
      options[:from] = from if from
      options[:to] = to if to
      options[:collapse] = ["digest"] unless all_timestamps

      cdx.snapshots(url, **options)
        .select { |snap| !snap.blocked? && snap.status_code == 200 }
    end

    def apply_filter(snapshots, filter)
      return snapshots unless filter

      snapshots.select { |snap| filter.match?(snap.original_url) }
    end

    def schedule_snapshots(snapshots, strategy)
      return snapshots unless strategy

      scheduler = DownloadScheduler.new(strategy: strategy)
      scheduler.schedule(snapshots)
    end

    def run_download(snapshots, resume, dry_run, page_requisites, progress)
      state = DownloadState.new(@output_dir)
      total = snapshots.size

      if @concurrency == 1
        download_sequential(snapshots, total, state, resume,
                            dry_run, page_requisites, progress)
      else
        download_concurrent(snapshots, total, state, resume,
                            dry_run, page_requisites, progress)
      end
    end

    def build_summary(start_time, total, downloaded, skipped,
                      bytes, failed: 0)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      DownloadSummary.new(
        total: total, downloaded: downloaded, skipped: skipped,
        failed: failed, bytes_written: bytes, elapsed: elapsed
      )
    end

    def download_sequential(snapshots, total, state, resume,
                            dry_run, page_requisites, progress)
      counters = { downloaded: 0, skipped: 0, bytes: 0, failed: 0 }

      snapshots.each_with_index do |snap, index|
        process_sequential(snap, state, resume, dry_run, counters)
        fetch_requisites(snap, dry_run, counters) if page_requisites
        progress&.call(index + 1, total, snap)
      end

      [counters[:downloaded], counters[:skipped],
       counters[:bytes], counters[:failed]]
    end

    def process_sequential(snap, state, resume, dry_run, counters)
      if resume && state.completed?(snap.timestamp)
        counters[:skipped] += 1
        return
      end

      counters[:bytes] += download_snapshot(snap, state) unless dry_run
      counters[:downloaded] += 1
    rescue StandardError => e
      counters[:failed] += 1
      @on_error&.call(snap, e)
    end

    def fetch_requisites(snap, dry_run, counters)
      return if dry_run

      begin
        bundle = snap.fetch_with_assets(client: @client)
        bundle.assets.downloadable.all.each do |asset_url|
          asset_snap = find_asset_snapshot(asset_url)
          next unless asset_snap

          counters[:bytes] += write_asset(asset_snap)
          counters[:downloaded] += 1
        end
      rescue StandardError
        nil
      end
    end

    def find_asset_snapshot(asset_url)
      cdx = @cdx_api || CdxApi.new(client: @client)
      cdx.near(asset_url, timestamp: Timestamp.now)
    rescue NoSnapshotFound, StandardError
      nil
    end

    def write_asset(snapshot)
      content = fetch_content(snapshot)
      filename = build_filename(snapshot)
      FileUtils.mkdir_p(File.dirname(filename))
      tmp_path = "#{filename}.tmp"
      File.binwrite(tmp_path, content)
      File.rename(tmp_path, filename)
      content.bytesize
    end

    def fetch_content(snapshot)
      @rate_limiter.wait(host: "web.archive.org")
      Fetcher.new(client: @client).fetch(
        snapshot.original_url, timestamp: snapshot.timestamp
      ).content
    end

    def download_snapshot(snap, state)
      content = fetch_and_save(snap)
      state.mark_completed(snap.timestamp, url: snap.original_url,
                                           bytes: content.bytesize)
      content.bytesize
    end

    def download_concurrent(snapshots, total, state, resume,
                            dry_run, page_requisites, progress)
      queue = snapshots.each_with_index.to_a
      shared = { mutex: Mutex.new, errors: [],
                 downloaded: 0, skipped: 0, bytes: 0, failed: 0 }

      threads = Array.new(@concurrency) do
        Thread.new do
          process_queue(queue, total, state, resume,
                        dry_run, page_requisites, progress, shared)
        end
      end
      threads.each(&:join)

      [shared[:downloaded], shared[:skipped],
       shared[:bytes], shared[:failed]]
    end

    def process_queue(queue, total, state, resume, dry_run,
                      _page_requisites, progress, shared)
      loop do
        snap, index = shared[:mutex].synchronize { queue.shift }
        break unless snap

        if skip_snapshot?(snap, state, resume, shared)
          progress&.call(index + 1, total, snap)
          next
        end

        concurrent_fetch(snap, dry_run, shared)
        progress&.call(index + 1, total, snap)
      end
    end

    def skip_snapshot?(snap, state, resume, shared)
      return false unless resume && state.completed?(snap.timestamp)

      shared[:mutex].synchronize { shared[:skipped] += 1 }
      true
    end

    def concurrent_fetch(snap, dry_run, shared)
      unless dry_run
        content = fetch_and_save(snap)
        record_completed(snap, content, shared)
      end
      shared[:mutex].synchronize { shared[:downloaded] += 1 }
    rescue StandardError => e
      shared[:mutex].synchronize do
        shared[:failed] += 1
        shared[:errors] << [snap, e]
      end
      @on_error&.call(snap, e)
    end

    def record_completed(snap, content, shared)
      shared[:mutex].synchronize do
        state.mark_completed(snap.timestamp,
                             url: snap.original_url,
                             bytes: content.bytesize)
        shared[:bytes] += content.bytesize
      end
    end

    def fetch_and_save(snapshot)
      page = fetch_page(snapshot)
      validate_page_status(page, snapshot)
      write_page_file(page, snapshot)
    end

    def fetch_page(snapshot)
      @rate_limiter.wait(host: "web.archive.org")
      Fetcher.new(client: @client).fetch(
        snapshot.original_url, timestamp: snapshot.timestamp
      )
    end

    def validate_page_status(page, snapshot)
      return if page.status_code.between?(200, 299)

      raise Error,
            "HTTP #{page.status_code} for " \
            "#{snapshot.original_url} at #{snapshot.timestamp}"
    end

    def write_page_file(page, snapshot)
      filename = build_filename(snapshot)
      FileUtils.mkdir_p(File.dirname(filename))
      tmp_path = "#{filename}.tmp"
      File.binwrite(tmp_path, page.content)
      File.rename(tmp_path, filename)
      page.content
    rescue StandardError
      FileUtils.rm_f(tmp_path) if defined?(tmp_path)
      raise
    end

    EXTENSION_MAP = {
      "text/html" => ".html",
      "text/css" => ".css",
      "text/plain" => ".txt",
      "text/javascript" => ".js",
      "application/javascript" => ".js",
      "application/x-javascript" => ".js",
      "application/json" => ".json",
      "application/xml" => ".xml",
      "application/pdf" => ".pdf",
      "application/octet-stream" => ".bin",
      "image/png" => ".png",
      "image/jpeg" => ".jpg",
      "image/gif" => ".gif",
      "image/svg+xml" => ".svg",
      "image/webp" => ".webp",
      "image/x-icon" => ".ico",
      "image/bmp" => ".bmp",
      "font/woff2" => ".woff2",
      "font/woff" => ".woff",
      "font/ttf" => ".ttf",
      "font/eot" => ".eot",
      "video/mp4" => ".mp4",
      "audio/mpeg" => ".mp3",
    }.freeze

    def extension_for(snapshot)
      mime = snapshot.mimetype.to_s.split(";").first.strip.downcase
      EXTENSION_MAP[mime] || ".bin"
    end

    def build_filename(snapshot)
      safe_path = @path_sanitizer.sanitize(snapshot.original_url)
      ts = snapshot.timestamp.to_s

      segments = safe_path.split(File::SEPARATOR)
      last = segments.pop || "index"

      File.join(@output_dir, *segments,
                "#{last}_#{ts}#{extension_for(snapshot)}")
    end
  end
end
