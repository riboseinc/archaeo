# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::CdxApi do
  def cdx_json_response(rows, resume_key: nil)
    header = Archaeo::CdxApi::ALL_FIELDS
    body_array = [header] + rows
    if resume_key
      body_array << []
      body_array << [resume_key]
    end
    body = JSON.generate(body_array)
    FakeHttpClient.response(status: 200, body: body)
  end

  let(:sample_rows) do
    [
      ["com,example)/", "20220113130051",
       "https://example.com/", "text/html",
       "200", "ABC", "12345"],
      ["com,example)/index.html", "20210601120000",
       "https://example.com/index.html", "text/html",
       "200", "DEF", "6789"],
    ]
  end

  let(:client) { described_class.new(client: fake_client) }

  describe "#snapshots" do
    context "with valid response" do
      let(:fake_client) do
        FakeHttpClient.new([cdx_json_response(sample_rows)])
      end

      it "returns an Enumerator of Snapshots" do
        results = client.snapshots("example.com")
        expect(results).to be_a(Enumerator)
        snapshots = results.to_a
        expect(snapshots.length).to eq(2)
        expect(snapshots).to all(be_a(Archaeo::Snapshot))
      end

      it "parses snapshot fields correctly" do
        snap = client.snapshots("example.com").first
        expect(snap.urlkey).to eq("com,example)/")
        expect(snap.timestamp).to be_a(Archaeo::Timestamp)
        expect(snap.timestamp.to_s).to eq("20220113130051")
        expect(snap.original_url).to eq("https://example.com/")
        expect(snap.mimetype).to eq("text/html")
        expect(snap.status_code).to eq(200)
        expect(snap.digest).to eq("ABC")
        expect(snap.length).to eq(12345)
      end

      it "sends correct query parameters" do
        client.snapshots("example.com",
                         from: Archaeo::Timestamp.new(year: 2020),
                         to: Archaeo::Timestamp.new(year: 2022),
                         match_type: "domain",
                         filters: ["statuscode:200"],
                         collapse: ["digest"],
                         sort: "reverse").to_a
        url = fake_client.last_url
        expect(url).to start_with(Archaeo::CdxApi::ENDPOINT)
        expect(url).to include("url=example.com")
        expect(url).to include("output=json")
        expect(url).to include("from=20200101000000")
        expect(url).to include("to=20220101000000")
        expect(url).to include("matchType=domain")
        expect(url).to include("filter0=statuscode%3A200")
        expect(url).to include("collapse0=digest")
        expect(url).to include("sort=reverse")
      end

      it "includes default CDX parameters" do
        client.snapshots("example.com").to_a
        url = fake_client.last_url
        expect(url).to include("output=json")
        expect(url).to include("showResumeKey=true")
        expect(url).to include("fl=")
      end

      it "disables gzip when gzip: false" do
        client.snapshots("example.com", gzip: false).to_a
        url = fake_client.last_url
        expect(url).to include("gzip=false")
      end

      it "normalizes URL whitespace before querying" do
        client.snapshots("  example.com  ").to_a
        url = fake_client.last_url
        expect(url).to include("url=example.com")
      end

      it "handles non-ASCII URLs" do
        client.snapshots("https://example.com/%C3%84").to_a
        url = fake_client.last_url
        expect(url).to include("url=https%3A%2F%2Fexample.com")
      end

      it "passes offset parameter" do
        client.snapshots("example.com", offset: 100).to_a
        url = fake_client.last_url
        expect(url).to include("offset=100")
      end
    end

    context "with resume key pagination" do
      it "fetches multiple pages" do
        page1_rows = [
          ["com,example)/", "20220113130051",
           "https://example.com/", "text/html", "200", "ABC", "12345"],
        ]
        page2_rows = [
          ["com,example)/", "20210601120000",
           "https://example.com/", "text/html", "200", "DEF", "6789"],
        ]
        responses = [
          cdx_json_response(page1_rows,
                            resume_key: "resume_token_page1"),
          cdx_json_response(page2_rows),
        ]
        fake = FakeHttpClient.new(responses)
        api = described_class.new(client: fake)

        snapshots = api.snapshots("example.com").to_a
        expect(snapshots.length).to eq(2)
        expect(snapshots[0].timestamp.to_s).to eq("20220113130051")
        expect(snapshots[1].timestamp.to_s).to eq("20210601120000")
      end

      it "passes resumeKey on subsequent requests" do
        page1 = cdx_json_response(sample_rows.first(1),
                                  resume_key: "token123")
        page2 = cdx_json_response(sample_rows.last(1))
        fake = FakeHttpClient.new([page1, page2])
        api = described_class.new(client: fake)

        api.snapshots("example.com").to_a
        # Second request URL should contain resumeKey
        urls = fake.all_urls
        expect(urls.length).to eq(2)
        expect(urls[1]).to include("resumeKey=token123")
      end

      it "stops when resume key is empty" do
        responses = [
          cdx_json_response(sample_rows, resume_key: ""),
        ]
        fake = FakeHttpClient.new(responses)
        api = described_class.new(client: fake)

        snapshots = api.snapshots("example.com").to_a
        expect(snapshots.length).to eq(2)
        expect(fake.all_urls.length).to eq(1)
      end
    end

    context "with page-based pagination" do
      let(:fake_client) do
        FakeHttpClient.new([cdx_json_response(sample_rows)])
      end

      it "fetches a specific page" do
        client.snapshots("example.com", page: 0).to_a
        url = fake_client.last_url
        expect(url).to include("page=0")
      end

      it "does not use showResumeKey for page queries" do
        client.snapshots("example.com", page: 0).to_a
        url = fake_client.last_url
        expect(url).to include("showResumeKey=true")
      end
    end

    context "with empty response" do
      let(:fake_client) do
        FakeHttpClient.new(
          [FakeHttpClient.response(status: 200, body: "")],
        )
      end

      it "returns an empty Enumerator" do
        results = client.snapshots("nonexistent.example.com").to_a
        expect(results).to be_empty
      end
    end

    context "with server error" do
      let(:fake_client) do
        FakeHttpClient.new([FakeHttpClient.response(status: 500)])
      end

      it "raises an error" do
        expect { client.snapshots("example.com").to_a }
          .to raise_error(Archaeo::Error, /HTTP 500/)
      end
    end

    context "with rate limit (503)" do
      let(:fake_client) do
        FakeHttpClient.new([FakeHttpClient.response(status: 503)])
      end

      it "raises RateLimitError" do
        expect { client.snapshots("example.com").to_a }
          .to raise_error(Archaeo::RateLimitError, /rate limited/)
      end
    end

    context "with invalid match_type" do
      let(:fake_client) { FakeHttpClient.new([]) }

      it "raises ArgumentError" do
        expect do
          client.snapshots("example.com", match_type: "invalid")
        end.to raise_error(ArgumentError, /Invalid match_type/)
      end
    end

    context "with invalid sort" do
      let(:fake_client) { FakeHttpClient.new([]) }

      it "raises ArgumentError" do
        expect do
          client.snapshots("example.com", sort: "invalid")
        end.to raise_error(ArgumentError, /Invalid sort/)
      end
    end

    context "with invalid filter field" do
      let(:fake_client) { FakeHttpClient.new([]) }

      it "raises ArgumentError" do
        expect do
          client.snapshots("example.com", filters: ["bogus:value"])
        end.to raise_error(ArgumentError, /Invalid CDX filter field/)
      end
    end

    context "with invalid collapse field" do
      let(:fake_client) { FakeHttpClient.new([]) }

      it "raises ArgumentError" do
        expect do
          client.snapshots("example.com", collapse: ["bogus"])
        end.to raise_error(ArgumentError, /Invalid collapse field/)
      end
    end

    context "with valid collapse field and N suffix" do
      let(:fake_client) do
        FakeHttpClient.new([cdx_json_response(sample_rows)])
      end

      it "accepts collapse with character limit" do
        client.snapshots("example.com", collapse: ["timestamp:10"]).to_a
        url = fake_client.last_url
        expect(url).to include("collapse0=timestamp%3A10")
      end
    end
  end

  describe "#near" do
    let(:fake_client) do
      FakeHttpClient.new([cdx_json_response(sample_rows)])
    end

    it "returns the closest snapshot" do
      snap = client.near("example.com",
                         timestamp: Archaeo::Timestamp.new(year: 2022))
      expect(snap).to be_a(Archaeo::Snapshot)
      expect(snap.original_url).to eq("https://example.com/")
    end

    it "raises BlockedSiteError for blocked snapshots" do
      blocked_rows = [
        ["com,blocked)/", "20220113130051",
         "https://blocked.com/", "text/html",
         "-1", "ABC", "12345"],
      ]
      fake = FakeHttpClient.new([cdx_json_response(blocked_rows)])
      api = described_class.new(client: fake)

      expect do
        api.near("blocked.com",
                 timestamp: Archaeo::Timestamp.new(year: 2022))
      end.to raise_error(Archaeo::BlockedSiteError, /blocked/)
    end

    it "sorts by closest and limits to 1" do
      client.near("example.com",
                  timestamp: Archaeo::Timestamp.new(year: 2022))
      url = fake_client.last_url
      expect(url).to include("sort=closest")
      expect(url).to include("limit=1")
    end
  end

  describe "#oldest" do
    let(:fake_client) do
      FakeHttpClient.new([cdx_json_response(sample_rows)])
    end

    it "searches near 1994-01-01" do
      client.oldest("example.com")
      url = fake_client.last_url
      expect(url).to include("closest=19940101000000")
    end
  end

  describe "#newest" do
    let(:fake_client) do
      FakeHttpClient.new([cdx_json_response(sample_rows)])
    end

    it "searches near current time" do
      client.newest("example.com")
      url = fake_client.last_url
      expect(url).to match(/closest=\d{14}/)
    end
  end

  describe "#before" do
    context "when snapshot exists before the timestamp" do
      let(:fake_client) do
        FakeHttpClient.new([cdx_json_response(sample_rows)])
      end

      it "returns the first snapshot before given timestamp" do
        ts = Archaeo::Timestamp.new(year: 2021, month: 12, day: 31)
        snap = client.before("example.com", timestamp: ts)
        expect(snap.timestamp.to_s).to eq("20210601120000")
      end
    end

    context "when no snapshot exists before the timestamp" do
      let(:fake_client) do
        FakeHttpClient.new([cdx_json_response(sample_rows)])
      end

      it "raises NoSnapshotFound" do
        ts = Archaeo::Timestamp.new(year: 1990)
        expect do
          client.before("example.com", timestamp: ts)
        end.to raise_error(Archaeo::NoSnapshotFound)
      end
    end
  end

  describe "#after" do
    context "when snapshot exists after the timestamp" do
      let(:fake_client) do
        FakeHttpClient.new([cdx_json_response(sample_rows)])
      end

      it "returns the first snapshot after given timestamp" do
        ts = Archaeo::Timestamp.new(year: 2021, month: 6, day: 1)
        snap = client.after("example.com", timestamp: ts)
        expect(snap.timestamp.to_s).to eq("20220113130051")
      end
    end

    context "when no snapshot exists after the timestamp" do
      let(:fake_client) do
        FakeHttpClient.new([cdx_json_response(sample_rows)])
      end

      it "raises NoSnapshotFound" do
        ts = Archaeo::Timestamp.new(year: 2030)
        expect do
          client.after("example.com", timestamp: ts)
        end.to raise_error(Archaeo::NoSnapshotFound)
      end
    end
  end

  describe "#num_pages" do
    it "returns the number of pages" do
      response = FakeHttpClient.response(status: 200, body: "42")
      fake = FakeHttpClient.new([response])
      api = described_class.new(client: fake)

      expect(api.num_pages("example.com")).to eq(42)
    end

    it "sends showNumPages=true" do
      response = FakeHttpClient.response(status: 200, body: "1")
      fake = FakeHttpClient.new([response])
      api = described_class.new(client: fake)

      api.num_pages("example.com")
      expect(fake.last_url).to include("showNumPages=true")
    end
  end

  describe "#unique_snapshots" do
    it "collapses by digest" do
      fake = FakeHttpClient.new([cdx_json_response(sample_rows)])
      api = described_class.new(client: fake)

      api.unique_snapshots("example.com").to_a
      url = fake.last_url
      expect(url).to include("collapse0=digest")
    end

    it "passes resolve_revisits by default" do
      fake = FakeHttpClient.new([cdx_json_response(sample_rows)])
      api = described_class.new(client: fake)

      api.unique_snapshots("example.com").to_a
      url = fake.last_url
      expect(url).to include("resolveRevisits=true")
    end
  end

  describe "#timeline" do
    it "returns a CdxTimeline" do
      fake = FakeHttpClient.new([cdx_json_response(sample_rows)])
      api = described_class.new(client: fake)

      timeline = api.timeline("example.com")
      expect(timeline).to be_a(Archaeo::CdxTimeline)
    end

    it "filters by status 200 by default" do
      fake = FakeHttpClient.new([cdx_json_response(sample_rows)])
      api = described_class.new(client: fake)

      api.timeline("example.com")
      url = fake.last_url
      expect(url).to include("filter0=statuscode%3A200")
    end

    it "accepts a custom bucket_size" do
      fake = FakeHttpClient.new([cdx_json_response(sample_rows)])
      api = described_class.new(client: fake)

      timeline = api.timeline("example.com", bucket_size: :year)
      expect(timeline).to be_a(Archaeo::CdxTimeline)
    end

    it "accepts from and to parameters" do
      fake = FakeHttpClient.new([cdx_json_response(sample_rows)])
      api = described_class.new(client: fake)

      api.timeline("example.com", from: "20220101", to: "20221231")
      url = fake.last_url
      expect(url).to include("from=20220101")
      expect(url).to include("to=20221231")
    end
  end

  describe "#known_urls" do
    it "returns unique original URLs" do
      rows = [
        ["com,example)/", "20220113130051",
         "https://example.com/", "text/html", "200", "ABC", "12345"],
        ["com,example)/about", "20220113130052",
         "https://example.com/about", "text/html", "200", "DEF", "6789"],
        ["com,example)/", "20220113130053",
         "https://example.com/", "text/html", "200", "GHI", "1111"],
      ]
      fake = FakeHttpClient.new([cdx_json_response(rows)])
      api = described_class.new(client: fake)

      urls = api.known_urls("example.com")
      expect(urls).to eq([
                           "https://example.com/",
                           "https://example.com/about",
                         ])
    end
  end
end
