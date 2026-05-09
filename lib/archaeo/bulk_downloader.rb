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
                   cdx_api: nil)
      @client = client
      @output_dir = output_dir
      @cdx_api = cdx_api
    end

    def download(url, from: nil, to: nil, resume: false)
      url = UrlNormalizer.normalize(url)
      FileUtils.mkdir_p(@output_dir)
      state = DownloadState.new(@output_dir)

      snapshots = fetch_snapshots(url, from: from, to: to)
      total = snapshots.size

      snapshots.each_with_index do |snap, index|
        next if resume && state.completed?(snap.timestamp)

        fetch_and_save(snap)
        state.mark_completed(snap.timestamp)

        yield index + 1, total, snap if block_given?
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

    def fetch_and_save(snapshot)
      fetcher = Fetcher.new(client: @client)
      page = fetcher.fetch(snapshot.original_url,
                           timestamp: snapshot.timestamp)

      filename = build_filename(snapshot)
      FileUtils.mkdir_p(File.dirname(filename))
      File.binwrite(filename, page.content)
    end

    EXTENSION_MAP = {
      "text/html" => ".html",
      "text/css" => ".css",
      "application/javascript" => ".js",
      "application/json" => ".json",
      "application/pdf" => ".pdf",
      "image/png" => ".png",
      "image/jpeg" => ".jpg",
      "image/gif" => ".gif",
      "image/svg+xml" => ".svg",
      "image/webp" => ".webp",
      "font/woff2" => ".woff2",
      "font/woff" => ".woff",
      "video/mp4" => ".mp4",
      "audio/mpeg" => ".mp3",
    }.freeze

    def extension_for(snapshot)
      EXTENSION_MAP[snapshot.mimetype] || ".bin"
    end

    def build_filename(snapshot)
      ts = snapshot.timestamp.to_s
      safe_path = snapshot.original_url
        .sub(%r{\Ahttps?://}, "")
        .gsub(%r{/}, File::SEPARATOR)
        .gsub(%r{[?&=]}, "_")
      safe_path = safe_path[0..-2] if safe_path.end_with?(File::SEPARATOR)
      safe_path = "#{safe_path}index" if safe_path.empty?

      File.join(@output_dir, safe_path, "#{ts}#{extension_for(snapshot)}")
    end
  end
end
