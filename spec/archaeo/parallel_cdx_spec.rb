# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::ParallelCdx do
  let(:fake_cdx) do
    snapshots = (0...6).map do |i|
      Archaeo::Snapshot.new(
        urlkey: "com,example)/page#{i}",
        timestamp: "202206#{format('%02d', 15 + i)}120000",
        original_url: "https://example.com/page#{i}",
        mimetype: "text/html",
        status_code: 200,
        digest: "SHA1-abc#{i}",
        length: 100 + i,
      )
    end

    cdx = instance_double(Archaeo::CdxApi)
    allow(cdx).to receive(:num_pages).and_return(3)
    allow(cdx).to receive(:snapshots) do |_url, **opts|
      page = opts[:page]
      if page
        idx = page * 2
        snapshots[idx, 2] || []
      else
        snapshots
      end
    end
    cdx
  end

  it "fetches pages in parallel and merges results" do
    parallel = described_class.new(cdx_api: fake_cdx, concurrency: 3)
    results = parallel.snapshots("example.com")
    expect(results.size).to eq(6)
    expect(results.map(&:original_url)).to all(include("example.com"))
  end

  it "falls back to single-page when only one page" do
    single_cdx = instance_double(Archaeo::CdxApi)
    allow(single_cdx).to receive_messages(num_pages: 1, snapshots: [])

    parallel = described_class.new(cdx_api: single_cdx, concurrency: 2)
    expect(single_cdx).to receive(:snapshots).and_return([])
    parallel.snapshots("example.com")
  end
end
