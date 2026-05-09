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
end
