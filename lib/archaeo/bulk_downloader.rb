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
                   cdx_api: nil, concurrency: 1)
      @client = client
      @output_dir = output_dir
      @cdx_api = cdx_api
      @concurrency = [1, concurrency.to_i].max
    end

    def download(url, from: nil, to: nil, resume: false,
                 dry_run: false, &block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      url = UrlNormalizer.normalize(url)
      FileUtils.mkdir_p(@output_dir) unless dry_run

      snapshots = fetch_snapshots(url, from: from, to: to)
      downloaded, skipped, bytes =
        run_download(snapshots, resume, dry_run, block)

      build_summary(start_time, snapshots.size, downloaded, skipped, bytes)
    end

    private

    def fetch_snapshots(url, from:, to:)
      cdx = @cdx_api || CdxApi.new(client: @client)
      options = {}
      options[:from] = from if from
      options[:to] = to if to
      cdx.snapshots(url, **options)
        .select { |snap| !snap.blocked? && snap.status_code == 200 }
    end

    def run_download(snapshots, resume, dry_run, progress)
      state = DownloadState.new(@output_dir)
      total = snapshots.size

      if @concurrency == 1
        download_sequential(snapshots, total, state, resume,
                            dry_run, progress)
      else
        download_concurrent(snapshots, total, state, resume,
                            dry_run, progress)
      end
    end

    def build_summary(start_time, total, downloaded, skipped, bytes)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      DownloadSummary.new(
        total: total, downloaded: downloaded, skipped: skipped,
        failed: 0, bytes_written: bytes, elapsed: elapsed
      )
    end

    def download_sequential(snapshots, total, state, resume,
                            dry_run, progress)
      counters = { downloaded: 0, skipped: 0, bytes: 0 }

      snapshots.each_with_index do |snap, index|
        process_sequential(snap, state, resume, dry_run, counters)
        progress&.call(index + 1, total, snap)
      end

      [counters[:downloaded], counters[:skipped], counters[:bytes]]
    end

    def process_sequential(snap, state, resume, dry_run, counters)
      if resume && state.completed?(snap.timestamp)
        counters[:skipped] += 1
        return
      end

      counters[:bytes] += download_snapshot(snap, state) unless dry_run
      counters[:downloaded] += 1
    end

    def download_snapshot(snap, state)
      content = fetch_and_save(snap)
      state.mark_completed(snap.timestamp, url: snap.original_url,
                                           bytes: content.bytesize)
      content.bytesize
    end

    def download_concurrent(snapshots, total, state, resume,
                            dry_run, progress)
      queue = snapshots.each_with_index.to_a
      shared = { mutex: Mutex.new, errors: [],
                 downloaded: 0, skipped: 0, bytes: 0 }

      threads = Array.new(@concurrency) do
        Thread.new do
          process_queue(queue, total, state, resume,
                        dry_run, progress, shared)
        end
      end
      threads.each(&:join)
      raise_on_errors(shared[:errors])

      [shared[:downloaded], shared[:skipped], shared[:bytes]]
    end

    def raise_on_errors(errors)
      return unless errors.any?

      raise Error,
            "#{errors.size} download(s) failed: " \
            "#{errors.map { |s, _| s.timestamp }.join(', ')}"
    end

    def process_queue(queue, total, state, resume, dry_run,
                      progress, shared)
      loop do
        snap, index = shared[:mutex].synchronize { queue.shift }
        break unless snap

        if skip_snapshot?(snap, state, resume, shared)
          progress&.call(index + 1, total, snap)
          next
        end

        concurrent_fetch(snap, state, dry_run, shared)
        progress&.call(index + 1, total, snap)
      end
    end

    def skip_snapshot?(snap, state, resume, shared)
      return false unless resume && state.completed?(snap.timestamp)

      shared[:mutex].synchronize { shared[:skipped] += 1 }
      true
    end

    def concurrent_fetch(snap, state, dry_run, shared)
      unless dry_run
        content = fetch_and_save(snap)
        shared[:mutex].synchronize do
          state.mark_completed(snap.timestamp,
                               url: snap.original_url,
                               bytes: content.bytesize)
          shared[:bytes] += content.bytesize
        end
      end
      shared[:mutex].synchronize { shared[:downloaded] += 1 }
    rescue StandardError => e
      shared[:mutex].synchronize { shared[:errors] << [snap, e] }
    end

    def fetch_and_save(snapshot)
      fetcher = Fetcher.new(client: @client)
      page = fetcher.fetch(snapshot.original_url,
                           timestamp: snapshot.timestamp)

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
      ts = snapshot.timestamp.to_s
      safe_path = snapshot.original_url
        .sub(%r{\Ahttps?://}, "")
        .gsub(%r{[<>:"|?*#]}, "_")
        .gsub(%r{[/\\]}, File::SEPARATOR)
        .gsub(%r{[?&=]}, "_")

      safe_path = safe_path[0..-2] if safe_path.end_with?(File::SEPARATOR)
      safe_path = "#{safe_path}index" if safe_path.empty?

      segments = safe_path.split(File::SEPARATOR).map do |seg|
        seg.length > 200 ? seg[0..200] : seg
      end

      File.join(@output_dir, *segments, "#{ts}#{extension_for(snapshot)}")
    end
  end
end
