# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::HttpClient do
  let(:client) { described_class.new(timeout: 5, max_retries: 2) }

  describe Archaeo::HttpClient::Response do
    it "stores status, headers, and body" do
      response = described_class.new(
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "hello",
      )
      expect(response.status).to eq(200)
      expect(response.headers).to eq({ "content-type" => "text/html" })
      expect(response.body).to eq("hello")
    end
  end

  describe "default configuration" do
    it "sets default timeout" do
      expect(described_class::DEFAULT_TIMEOUT).to eq(30)
    end

    it "sets default max retries" do
      expect(described_class::DEFAULT_MAX_RETRIES).to eq(3)
    end

    it "has realistic user agent profiles" do
      expect(described_class::USER_AGENT_PROFILES.length).to be >= 3
      expect(described_class::USER_AGENT_PROFILES).to all(include("Mozilla"))
    end
  end

  describe "user agent", :network do
    it "makes an HTTP GET request" do
      response = client.get("https://httpbin.org/get")
      expect(response.status).to eq(200)
      expect(response.body).to include("httpbin.org")
    end

    it "handles 404 responses" do
      response = client.get("https://httpbin.org/status/404")
      expect(response.status).to eq(404)
    end
  end

  describe "#shutdown" do
    it "does not raise when no connections exist" do
      fresh = described_class.new
      expect { fresh.shutdown }.not_to raise_error
    end
  end

  describe "retry behavior" do
    it "raises MaximumRetriesExceeded after exhausting retries" do
      short_client = described_class.new(
        timeout: 1, max_retries: 1, retry_delay: 0,
      )
      expect do
        short_client.get("https://192.0.2.1/")
      end.to raise_error(Archaeo::MaximumRetriesExceeded)
    end
  end

  describe "gzip decompression", :network do
    it "decompresses gzip responses" do
      response = client.get("https://httpbin.org/gzip")
      expect(response.status).to eq(200)
      body = JSON.parse(response.body)
      expect(body["gzipped"]).to be true
    end
  end
end
