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

  describe "before_request callback" do
    it "calls before_request with uri and request" do
      captured = nil
      tracking_client = described_class.new(
        timeout: 5, max_retries: 0,
        before_request: ->(uri, req) { captured = [uri.to_s, req.path] }
      )
      begin
        tracking_client.get("https://httpbin.org/get")
      rescue StandardError
        nil
      end
      expect(captured).not_to be_nil
      tracking_client.shutdown
    end
  end

  describe "on_request callback with retry count" do
    it "passes the retry count to the callback" do
      captured = nil
      tracking_client = described_class.new(
        timeout: 5, max_retries: 0,
        on_request: ->(_uri, _elapsed, _status, retries) { captured = retries }
      )
      tracking_client.get("https://httpbin.org/get")
      expect(captured).to eq(0)
      tracking_client.shutdown
    end
  end

  describe "rate limiter integration" do
    it "calls rate limiter wait before requests" do
      limiter = Archaeo::RateLimiter.new(min_interval: 0)
      expect(limiter).to receive(:wait).with(host: "httpbin.org")
      rate_client = described_class.new(
        timeout: 5, max_retries: 0, rate_limiter: limiter,
      )
      rate_client.get("https://httpbin.org/get")
      rate_client.shutdown
    end

    it "works without a rate limiter" do
      no_limiter_client = described_class.new(timeout: 5, max_retries: 0)
      response = no_limiter_client.get("https://httpbin.org/get")
      expect(response.status).to eq(200)
      no_limiter_client.shutdown
    end
  end
end
