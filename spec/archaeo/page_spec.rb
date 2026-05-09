# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::Page do
  subject do
    described_class.new(
      content: "<html>Hello</html>",
      content_type: "text/html",
      status_code: 200,
      archive_url: "https://web.archive.org/web/20220615000000/" \
                   "https://example.com/",
      original_url: "https://example.com/",
      timestamp: ts,
    )
  end

  let(:ts) { Archaeo::Timestamp.new(year: 2022, month: 6, day: 15) }

  it "exposes content" do
    expect(subject.content).to eq("<html>Hello</html>")
  end

  it "exposes content_type" do
    expect(subject.content_type).to eq("text/html")
  end

  it "exposes status_code" do
    expect(subject.status_code).to eq(200)
  end

  it "exposes archive_url" do
    expect(subject.archive_url).to include("web.archive.org")
  end

  it "exposes original_url" do
    expect(subject.original_url).to eq("https://example.com/")
  end

  it "exposes timestamp as a Timestamp" do
    expect(subject.timestamp).to be_a(Archaeo::Timestamp)
    expect(subject.timestamp).to eq(ts)
  end

  it "coerces string timestamps" do
    page = described_class.new(
      content: "",
      content_type: "text/plain",
      status_code: 200,
      archive_url: "https://web.archive.org/web/20220101000000/" \
                   "https://example.com/",
      original_url: "https://example.com/",
      timestamp: "20220101000000",
    )
    expect(page.timestamp).to be_a(Archaeo::Timestamp)
  end
end
