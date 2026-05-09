# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::Fetcher do
  let(:fake_client) { FakeHttpClient.new(@responses) }
  let(:fetcher) { described_class.new(client: fake_client) }
  let(:timestamp) { Archaeo::Timestamp.new(year: 2022, month: 6, day: 15) }

  describe "#fetch" do
    context "with a successful response" do
      before do
        @responses = [
          FakeHttpClient.response(
            status: 200,
            headers: { "content-type" => "text/html" },
            body: "<html><body>Hello</body></html>",
          ),
        ]
      end

      it "returns a Page with content and metadata" do
        result = fetcher.fetch("https://example.com/",
                               timestamp: timestamp)
        expect(result).to be_a(Archaeo::Page)
        expect(result.content).to eq("<html><body>Hello</body></html>")
        expect(result.content_type).to eq("text/html")
        expect(result.status_code).to eq(200)
        expect(result.archive_url).to include("web.archive.org")
        expect(result.original_url).to eq("https://example.com/")
        expect(result.timestamp).to eq(timestamp)
      end

      it "constructs the correct archive URL" do
        fetcher.fetch("https://example.com/", timestamp: timestamp)
        expect(fake_client.last_url).to eq(
          "https://web.archive.org/web/" \
          "20220615000000/https://example.com/",
        )
      end
    end

    context "with identity mode" do
      before do
        @responses = [
          FakeHttpClient.response(status: 200, body: "raw content"),
        ]
      end

      it "uses id_/ prefix in the URL" do
        fetcher.fetch("https://example.com/",
                      timestamp: timestamp, identity: true)
        expect(fake_client.last_url).to eq(
          "https://web.archive.org/web/" \
          "20220615000000id_/https://example.com/",
        )
      end
    end

    context "with redirects" do
      before do
        @responses = [
          FakeHttpClient.response(
            status: 302,
            headers: {
              "location" => "/web/20220615000000id_/https://example.com/",
            },
            body: "",
          ),
          FakeHttpClient.response(
            status: 200,
            headers: { "content-type" => "text/html" },
            body: "redirected content",
          ),
        ]
      end

      it "follows redirects" do
        result = fetcher.fetch("https://example.com/",
                               timestamp: timestamp)
        expect(result.status_code).to eq(200)
        expect(result.content).to eq("redirected content")
      end

      it "resolves relative redirect URLs" do
        fetcher.fetch("https://example.com/", timestamp: timestamp)
        expect(fake_client.last_url).to eq(
          "https://web.archive.org/web/" \
          "20220615000000id_/https://example.com/",
        )
      end
    end

    context "with too many redirects" do
      before do
        redirect = FakeHttpClient.response(
          status: 302,
          headers: {
            "location" => "/web/20220615000000/https://example.com/",
          },
          body: "",
        )
        @responses = Array.new(10, redirect)
      end

      it "raises an error" do
        expect do
          fetcher.fetch("https://example.com/", timestamp: timestamp)
        end.to raise_error(Archaeo::Error, /Too many redirects/)
      end
    end

    context "with string timestamp" do
      before do
        @responses = [
          FakeHttpClient.response(status: 200, body: "ok"),
        ]
      end

      it "coerces string to Timestamp" do
        result = fetcher.fetch("https://example.com/",
                               timestamp: "20220113130051")
        expect(result.timestamp.to_s).to eq("20220113130051")
      end
    end

    context "with 404 response" do
      before do
        @responses = [
          FakeHttpClient.response(status: 404, body: "Not Found"),
        ]
      end

      it "returns a Page with 404 status" do
        result = fetcher.fetch("https://example.com/missing",
                               timestamp: timestamp)
        expect(result.status_code).to eq(404)
      end
    end

    context "with non-ASCII URL" do
      before do
        @responses = [
          FakeHttpClient.response(
            status: 200,
            headers: { "content-type" => "text/html" },
            body: "unicode content",
          ),
        ]
      end

      it "handles percent-encoded URLs" do
        result = fetcher.fetch(
          "https://example.com/%C3%84", timestamp: timestamp
        )
        expect(result.status_code).to eq(200)
        expect(fake_client.last_url).to include("%C3%84")
      end
    end
  end
end
