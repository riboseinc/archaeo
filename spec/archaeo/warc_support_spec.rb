# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "zlib"

RSpec.describe Archaeo::WarcWriter do
  let(:ts) { Archaeo::Timestamp.new(year: 2022, month: 6, day: 15) }

  let(:pages) do
    [
      Archaeo::Page.new(
        content: "<html>Hello</html>",
        content_type: "text/html",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/https://example.com/",
        original_url: "https://example.com/",
        timestamp: ts,
      ),
      Archaeo::Page.new(
        content: "body { color: red; }",
        content_type: "text/css",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/https://example.com/style.css",
        original_url: "https://example.com/style.css",
        timestamp: ts,
      ),
    ]
  end

  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  it "writes a valid WARC file" do
    path = File.join(tmpdir, "test.warc")
    described_class.new.write(path, pages)
    content = File.read(path)
    expect(content).to include("WARC/1.0")
    expect(content).to include("WARC-Type: warcinfo")
    expect(content).to include("WARC-Type: response")
    expect(content).to include("https://example.com/")
    expect(content).to include("<html>Hello</html>")
  end

  it "writes a gzip-compressed WARC file" do
    path = File.join(tmpdir, "test.warc.gz")
    described_class.new.write(path, pages)
    expect(File.exist?(path)).to be true
    content = Zlib::GzipReader.open(path, &:read)
    expect(content).to include("WARC/1.0")
  end

  it "includes warcinfo record" do
    path = File.join(tmpdir, "test.warc")
    described_class.new.write(path, [pages.first])
    content = File.read(path)
    expect(content).to include("software: archaeo/")
    expect(content).to include("WARC File Format 1.0")
  end
end

RSpec.describe Archaeo::WarcReader do
  let(:ts) { Archaeo::Timestamp.new(year: 2022, month: 6, day: 15) }

  let(:pages) do
    [
      Archaeo::Page.new(
        content: "<html>Test content</html>",
        content_type: "text/html",
        status_code: 200,
        archive_url: "https://web.archive.org/web/20220615000000/https://example.com/",
        original_url: "https://example.com/",
        timestamp: ts,
      ),
    ]
  end

  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  it "reads records from a WARC file written by WarcWriter" do
    path = File.join(tmpdir, "roundtrip.warc")
    Archaeo::WarcWriter.new.write(path, pages)

    reader = described_class.new
    records = reader.read_records(path)
    expect(records.size).to be >= 2

    info = records.find(&:warcinfo?)
    expect(info).not_to be_nil
    expect(info.body).to include("archaeo")

    resp = records.find(&:response?)
    expect(resp).not_to be_nil
    expect(resp.target_uri).to eq("https://example.com/")
  end

  it "reads gzipped WARC files" do
    path = File.join(tmpdir, "roundtrip.warc.gz")
    Archaeo::WarcWriter.new.write(path, pages, compress: true)

    reader = described_class.new
    records = reader.read_records(path)
    expect(records.size).to be >= 1
  end

  it "yields records via block" do
    path = File.join(tmpdir, "block.warc")
    Archaeo::WarcWriter.new.write(path, pages)

    yielded = []
    described_class.new.read(path) { |r| yielded << r }
    expect(yielded.size).to be >= 1
  end
end

RSpec.describe Archaeo::WarcRecord do
  it "exposes accessor methods" do
    record = described_class.new(
      version: "1.0",
      headers: { warc_type: "response",
                 warc_target_uri: "https://example.com/" },
      body: "content",
    )
    expect(record.response?).to be true
    expect(record.warcinfo?).to be false
    expect(record.target_uri).to eq("https://example.com/")
  end

  it "serializes to hash" do
    record = described_class.new(
      version: "1.0", headers: {}, body: "test",
    )
    h = record.to_h
    expect(h[:version]).to eq("1.0")
    expect(h[:body_length]).to eq(4)
  end
end
