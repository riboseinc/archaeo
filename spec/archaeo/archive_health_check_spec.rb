# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::ArchiveHealthCheck do
  let(:snapshot) do
    Archaeo::Snapshot.new(
      urlkey: "com,example)/", timestamp: "20220615000000",
      original_url: "https://example.com/", mimetype: "text/html",
      status_code: 200, digest: "abc", length: "1000"
    )
  end

  describe "#check" do
    it "reports all snapshots as accessible" do
      head_responses = [
        FakeHttpClient.response(status: 200),
        FakeHttpClient.response(status: 200),
      ]
      fake_client = FakeHttpClient.new(head_responses)

      cdx_api = FakeCdxApiWithSnapshots.new([snapshot, snapshot])
      checker = described_class.new(client: fake_client, cdx_api: cdx_api)
      report = checker.check("example.com")
      expect(report.total).to eq(2)
      expect(report.accessible).to eq(2)
      expect(report.missing).to eq(0)
    end

    it "reports missing snapshots" do
      head_responses = [FakeHttpClient.response(status: 404)]
      fake_client = FakeHttpClient.new(head_responses)

      cdx_api = FakeCdxApiWithSnapshots.new([snapshot])
      checker = described_class.new(client: fake_client, cdx_api: cdx_api)
      report = checker.check("example.com")
      expect(report.total).to eq(1)
      expect(report.missing).to eq(1)
    end
  end
end

class FakeCdxApiWithSnapshots
  def initialize(snapshots)
    @snapshots = snapshots
  end

  def snapshots(_url, **)
    @snapshots.select(&:success?)
  end
end
