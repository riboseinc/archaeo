# frozen_string_literal: true

require "fileutils"

module Archaeo
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

    def download(url, from: nil, to: nil, resume: false, &block)
      url = UrlNormalizer.normalize(url)
      FileUtils.mkdir_p(@output_dir)
      state = DownloadState.new(@output_dir)

      snapshots = fetch_snapshots(url, from: from, to: to)
      total = snapshots.size
      progress = block

      if @concurrency == 1
        download_sequential(snapshots, total, state, resume, progress)
      else
        download_concurrent(snapshots, total, state, resume, progress)
      end
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

    def download_sequential(snapshots, total, state, resume, progress)
      snapshots.each_with_index do |snap, index|
        next if resume && state.completed?(snap.timestamp)

        fetch_and_save(snap)
        state.mark_completed(snap.timestamp)

        progress&.call(index + 1, total, snap)
      end
    end

    def download_concurrent(snapshots, total, state, resume, progress)
      queue = snapshots.each_with_index.to_a
      mutex = Mutex.new
      errors = []

      threads = Array.new(@concurrency) do
        Thread.new do
          process_queue(queue, total, state, resume, progress, mutex, errors)
        end
      end
      threads.each(&:join)

      return unless errors.any?

      raise Error,
            "#{errors.size} download(s) failed: " \
            "#{errors.map { |s, _| s.timestamp }.join(', ')}"
    end

    def process_queue(queue, total, state, resume, progress, mutex, errors)
      loop do
        snap, index = mutex.synchronize { queue.shift }
        break unless snap

        next if resume && state.completed?(snap.timestamp)

        begin
          fetch_and_save(snap)
          state.mark_completed(snap.timestamp)
        rescue StandardError => e
          mutex.synchronize { errors << [snap, e] }
        end

        progress&.call(index + 1, total, snap)
      end
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
