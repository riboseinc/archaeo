# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::SaveApi do
  def save_response(status: 200, headers: {}, body: "")
    FakeHttpClient.response(status: status, headers: headers,
                            body: body)
  end

  let(:fake_client) { FakeHttpClient.new(@responses) }
  let(:api) { described_class.new(client: fake_client) }

  describe "#save" do
    context "when save succeeds with Content-Location header" do
      before do
        @responses = [
          save_response(headers: {
                          "content-location" => "/web/20220615120000/https://example.com/",
                        }),
        ]
      end

      it "returns a SaveResult with the archive URL" do
        result = api.save("https://example.com/")
        expect(result).to be_a(Archaeo::SaveResult)
        expect(result.archive_url).to eq(
          "https://web.archive.org/web/" \
          "20220615120000/https://example.com/",
        )
        expect(result.timestamp).to be_a(Archaeo::Timestamp)
        expect(result.timestamp.to_s).to eq("20220615120000")
      end
    end

    context "when save succeeds with memento link header" do
      before do
        @responses = [
          save_response(headers: {
                          "link" => 'rel="memento" href="web.archive.org/' \
                                    'web/20220615120000/https://example.com/">',
                        }),
        ]
      end

      it "extracts archive URL from memento link" do
        result = api.save("https://example.com/")
        expect(result.archive_url).to eq(
          "https://web.archive.org/web/" \
          "20220615120000/https://example.com/",
        )
      end
    end

    context "when rate limited (429)" do
      before { @responses = [save_response(status: 429)] }

      it "raises RateLimitError" do
        expect { api.save("https://example.com/") }
          .to raise_error(Archaeo::RateLimitError, /Rate limited/)
      end
    end

    context "when session limit reached (509)" do
      before { @responses = [save_response(status: 509)] }

      it "raises SaveFailed" do
        expect { api.save("https://example.com/") }
          .to raise_error(Archaeo::SaveFailed, /Session limit/)
      end
    end

    context "when save needs retries" do
      before do
        @responses = [
          save_response(status: 200, headers: {}, body: ""),
          save_response(headers: {
                          "content-location" => "/web/20220615120000/https://example.com/",
                        }),
        ]
      end

      it "retries and eventually succeeds" do
        result = api.save("https://example.com/")
        expect(result.archive_url).to include("web.archive.org")
      end
    end

    context "when max retries exceeded" do
      before do
        @responses = Array.new(10) do
          save_response(status: 200, headers: {}, body: "")
        end
      end

      it "raises MaximumRetriesExceeded" do
        expect { api.save("https://example.com/") }
          .to raise_error(Archaeo::MaximumRetriesExceeded,
                          /Failed to save/)
      end
    end

    it "detects cached saves" do
      old_ts = (Time.now.utc - 7200).strftime("%Y%m%d%H%M%S")
      @responses = [
        save_response(headers: {
                        "content-location" => "/web/#{old_ts}/https://example.com/",
                      }),
      ]

      result = api.save("https://example.com/")
      expect(result).to be_cached
    end
  end
end
