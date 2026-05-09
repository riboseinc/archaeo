# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::AvailabilityApi do
  def availability_response(available: true, url: "https://example.com/",
                            timestamp: "20220113130051", status: "200")
    body = if available
             JSON.generate({
                             "url" => "example.com",
                             "archived_snapshots" => {
                               "closest" => {
                                 "url" => "https://web.archive.org/web/#{timestamp}/#{url}",
                                 "timestamp" => timestamp,
                                 "status" => status,
                                 "available" => true,
                               },
                             },
                           })
           else
             JSON.generate({
                             "url" => "example.com",
                             "archived_snapshots" => {},
                           })
           end
    FakeHttpClient.response(status: 200, body: body)
  end

  let(:fake_client) { FakeHttpClient.new(@responses) }
  let(:api) { described_class.new(client: fake_client) }

  describe "#near" do
    context "when archive is available" do
      before { @responses = [availability_response] }

      it "returns an AvailabilityResult" do
        result = api.near("example.com")
        expect(result).to be_a(Archaeo::AvailabilityResult)
        expect(result).to be_available
        expect(result.archive_url).to include("web.archive.org")
        expect(result.timestamp).to be_a(Archaeo::Timestamp)
        expect(result.url).to eq("example.com")
      end
    end

    context "when no archive exists" do
      before do
        @responses = [availability_response(available: false)]
      end

      it "returns a non-available result" do
        result = api.near("example.com")
        expect(result).not_to be_available
        expect(result.archive_url).to be_nil
      end
    end

    context "with timestamp parameter" do
      before { @responses = [availability_response] }

      it "passes timestamp to the API" do
        ts = Archaeo::Timestamp.new(year: 2022, month: 6)
        api.near("example.com", timestamp: ts)
        url = fake_client.last_url
        expect(url).to include("timestamp=20220601000000")
      end
    end

    context "with HTTP error" do
      before do
        @responses = [FakeHttpClient.response(status: 500)]
      end

      it "raises InvalidResponse" do
        expect { api.near("example.com") }
          .to raise_error(Archaeo::InvalidResponse, /HTTP 500/)
      end
    end
  end

  describe "#oldest" do
    before do
      @responses = [
        availability_response(timestamp: "19960101000000"),
      ]
    end

    it "queries near 1994-01-01" do
      api.oldest("example.com")
      expect(fake_client.last_url).to include(
        "timestamp=19940101000000",
      )
    end
  end

  describe "#newest" do
    before do
      @responses = [
        availability_response(timestamp: "20240615120000"),
      ]
    end

    it "queries near current time" do
      api.newest("example.com")
      expect(fake_client.last_url).to match(/timestamp=\d{14}/)
    end
  end

  describe "#available?" do
    context "when archive exists" do
      before { @responses = [availability_response] }

      it "returns true" do
        expect(api.available?("example.com")).to be true
      end
    end

    context "when no archive exists" do
      before do
        @responses = [availability_response(available: false)]
      end

      it "returns false" do
        expect(api.available?("example.com")).to be false
      end
    end
  end

  describe "https enforcement" do
    it "forces https on archive URLs" do
      body = JSON.generate({
                             "url" => "example.com",
                             "archived_snapshots" => {
                               "closest" => {
                                 "url" => "http://web.archive.org/web/" \
                                          "20220113130051/https://example.com/",
                                 "timestamp" => "20220113130051",
                                 "status" => "200",
                                 "available" => true,
                               },
                             },
                           })
      @responses = [FakeHttpClient.response(status: 200, body: body)]

      result = api.near("example.com")
      expect(result.archive_url).to start_with("https://")
    end
  end

  describe "rate limit handling" do
    it "raises RateLimitError on 503" do
      @responses = [FakeHttpClient.response(status: 503)]
      expect { api.near("example.com") }
        .to raise_error(Archaeo::RateLimitError, /rate limited/)
    end
  end
end
