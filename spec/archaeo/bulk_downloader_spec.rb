# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Archaeo::BulkDownloader do
  def cdx_response(rows)
    header = Archaeo::CdxApi::ALL_FIELDS
    body = JSON.generate([header] + rows)
    FakeHttpClient.response(status: 200, body: body)
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:sample_rows) do
    [
      ["com,example)/", "20220113130051",
       "https://example.com/", "text/html",
       "200", "ABC", "12345"],
    ]
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe "#download" do
    it "downloads snapshots to the output directory" do
      cdx_resp = cdx_response(sample_rows)
      fetch_resp = FakeHttpClient.response(
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "<html>hello</html>",
      )
      fake = FakeHttpClient.new([cdx_resp, fetch_resp])
      downloader = described_class.new(
        client: fake, output_dir: tmpdir,
      )

      downloader.download("example.com")
      files = Dir.glob(File.join(tmpdir, "**", "*.html"))
      expect(files.length).to eq(1)
      expect(File.read(files[0])).to eq("<html>hello</html>")
    end

    it "skips blocked snapshots" do
      blocked_row = [
        "com,blocked)/", "20220113130051",
        "https://blocked.com/", "text/html",
        "-1", "ABC", "12345"
      ]
      normal_row = sample_rows[0]
      cdx_resp = cdx_response([blocked_row, normal_row])
      fetch_resp = FakeHttpClient.response(
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "ok",
      )
      fake = FakeHttpClient.new([cdx_resp, fetch_resp])
      downloader = described_class.new(
        client: fake, output_dir: tmpdir,
      )

      downloader.download("example.com")
      files = Dir.glob(File.join(tmpdir, "**", "*.html"))
      expect(files.length).to eq(1)
    end

    it "yields progress" do
      cdx_resp = cdx_response(sample_rows)
      fetch_resp = FakeHttpClient.response(
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "ok",
      )
      fake = FakeHttpClient.new([cdx_resp, fetch_resp])
      downloader = described_class.new(
        client: fake, output_dir: tmpdir,
      )

      progress = []
      downloader.download("example.com") do |current, total, snap|
        progress << [current, total, snap.original_url]
      end
      expect(progress.length).to eq(1)
      expect(progress[0][0]).to eq(1)
      expect(progress[0][1]).to eq(1)
    end

    it "resumes from state" do
      # Mark snapshot as already completed
      state = Archaeo::DownloadState.new(tmpdir)
      state.mark_completed(
        Archaeo::Timestamp.parse("20220113130051"),
      )

      # The CDX query still returns the snapshot
      cdx_resp = cdx_response(sample_rows)
      # No fetch response needed since it's skipped
      fake = FakeHttpClient.new([cdx_resp])
      downloader = described_class.new(
        client: fake, output_dir: tmpdir,
      )

      downloader.download("example.com", resume: true)
      files = Dir.glob(File.join(tmpdir, "**", "*.html"))
      expect(files.length).to eq(0)
    end

    it "filters by date range" do
      rows = [
        ["com,example)/", "20220113130051",
         "https://example.com/", "text/html", "200", "ABC", "12345"],
        ["com,example)/", "20210601120000",
         "https://example.com/", "text/html", "200", "DEF", "6789"],
      ]
      cdx_resp = cdx_response(rows)
      fetch_resp = FakeHttpClient.response(
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "ok",
      )
      fake = FakeHttpClient.new([cdx_resp, fetch_resp])
      downloader = described_class.new(
        client: fake, output_dir: tmpdir,
      )

      downloader.download("example.com",
                          from: "20220101", to: "20221231")
      url = fake.all_urls.first
      expect(url).to include("from=20220101")
      expect(url).to include("to=20221231")
    end

    it "uses mimetype-aware file extensions" do
      css_row = [
        "com,example)/style.css", "20220113130051",
        "https://example.com/style.css", "text/css",
        "200", "ABC", "12345"
      ]
      cdx_resp = cdx_response([css_row])
      fetch_resp = FakeHttpClient.response(
        status: 200,
        headers: { "content-type" => "text/css" },
        body: "body { color: red; }",
      )
      fake = FakeHttpClient.new([cdx_resp, fetch_resp])
      downloader = described_class.new(
        client: fake, output_dir: tmpdir,
      )

      downloader.download("example.com")
      files = Dir.glob(File.join(tmpdir, "**", "*.css"))
        .select { |f| File.file?(f) }
      expect(files.length).to eq(1)
    end

    it "tracks failed downloads via on_error callback" do
      cdx_resp = cdx_response(sample_rows)
      fetch_resp = FakeHttpClient.response(
        status: 500, body: "Internal Server Error",
      )
      fake = FakeHttpClient.new([cdx_resp, fetch_resp])
      errors = []
      downloader = described_class.new(
        client: fake, output_dir: tmpdir,
        on_error: ->(snap, err) { errors << [snap, err] }
      )

      downloader.download("example.com")
      expect(errors.length).to eq(1)
    end

    it "accepts custom CdxApi via constructor" do
      single_row = [
        ["com,example)/", "20220113130051",
         "https://example.com/", "text/html",
         "200", "ABC", "12345"],
      ]
      cdx_resp = cdx_response(single_row)
      fetch_resp = FakeHttpClient.response(
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "ok",
      )
      fake = FakeHttpClient.new([cdx_resp, fetch_resp])
      custom_cdx = Archaeo::CdxApi.new(client: fake)
      downloader = described_class.new(
        client: fake, output_dir: tmpdir, cdx_api: custom_cdx,
      )

      downloader.download("example.com")
      files = Dir.glob(File.join(tmpdir, "**", "*"))
        .select { |f| File.file?(f) }
      expect(files.length).to eq(1)
    end
  end
end
