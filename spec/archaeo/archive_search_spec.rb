# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::ArchiveSearch do
  let(:snapshot) do
    Archaeo::Snapshot.new(
      urlkey: "com,example)/",
      timestamp: "20220615000000",
      original_url: "https://example.com/",
      mimetype: "text/html", status_code: 200,
      digest: "SHA1-abc", length: 200
    )
  end

  let(:page) do
    Archaeo::Page.new(
      content: "<html><body>Contact us at info@example.com</body></html>",
      content_type: "text/html",
      status_code: 200,
      archive_url: "https://web.archive.org/web/20220615000000/https://example.com/",
      original_url: "https://example.com/",
      timestamp: Archaeo::Timestamp.new(year: 2022, month: 6, day: 15),
    )
  end

  let(:fake_cdx) do
    cdx = instance_double(Archaeo::CdxApi)
    allow(cdx).to receive(:snapshots).and_return([snapshot])
    cdx
  end

  let(:fake_fetcher) do
    fetcher = instance_double(Archaeo::Fetcher)
    allow(fetcher).to receive(:fetch).and_return(page)
    fetcher
  end

  let(:searcher) do
    described_class.new(cdx_api: fake_cdx, fetcher: fake_fetcher)
  end

  it "finds matching text in snapshots" do
    results = searcher.search("example.com", query: "Contact us")
    expect(results.size).to be >= 1
    expect(results.first.context).to include("Contact us")
  end

  it "returns empty results for no matches" do
    results = searcher.search("example.com", query: "xyzzy-no-match")
    expect(results).to be_empty
  end

  it "raises on empty query" do
    expect { searcher.search("example.com", query: "") }
      .to raise_error(ArgumentError)
  end

  it "respects max_results limit" do
    results = searcher.search("example.com", query: "example", max_results: 1)
    expect(results.size).to be <= 1
  end

  it "performs case-insensitive search by default" do
    results = searcher.search("example.com", query: "contact us")
    expect(results).not_to be_empty
  end

  it "respects case_sensitive option" do
    results = searcher.search("example.com", query: "contact us",
                                             case_sensitive: true)
    expect(results).to be_empty
  end
end

RSpec.describe Archaeo::SearchResult do
  it "serializes to hash" do
    snap = Archaeo::Snapshot.new(
      urlkey: "com,example)/",
      timestamp: "20220615000000",
      original_url: "https://example.com/",
      mimetype: "text/html", status_code: 200
    )
    result = described_class.new(
      url: "https://example.com/",
      snapshot: snap,
      context: "...Contact us...",
      match_offset: 10,
    )
    h = result.to_h
    expect(h[:url]).to eq("https://example.com/")
    expect(h[:context]).to eq("...Contact us...")
  end

  it "serializes to JSON" do
    snap = Archaeo::Snapshot.new(
      urlkey: "com,example)/",
      timestamp: "20220615000000",
      original_url: "https://example.com/",
      mimetype: "text/html", status_code: 200
    )
    result = described_class.new(
      url: "https://example.com/",
      snapshot: snap,
      context: "test",
      match_offset: 0,
    )
    expect { JSON.generate(result.as_json) }.not_to raise_error
  end
end
