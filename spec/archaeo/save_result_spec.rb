# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::SaveResult do
  subject do
    described_class.new(
      archive_url: "https://web.archive.org/web/20220615120000/" \
                   "https://example.com/",
      timestamp: ts,
      cached: false,
    )
  end

  let(:ts) { Archaeo::Timestamp.new(year: 2022, month: 6, day: 15) }

  it "exposes archive_url" do
    expect(subject.archive_url).to include("web.archive.org")
  end

  it "exposes timestamp as a Timestamp" do
    expect(subject.timestamp).to be_a(Archaeo::Timestamp)
  end

  it "reports cached status" do
    expect(subject).not_to be_cached
  end

  it "reports cached true when appropriate" do
    result = described_class.new(
      archive_url: "https://web.archive.org/web/20220615120000/" \
                   "https://example.com/",
      timestamp: ts,
      cached: true,
    )
    expect(result).to be_cached
  end
end
