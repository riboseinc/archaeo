# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::AvailabilityResult do
  let(:ts) { Archaeo::Timestamp.new(year: 2022, month: 1, day: 13) }

  it "reports available when archive exists" do
    result = described_class.new(
      url: "example.com",
      available: true,
      archive_url: "https://web.archive.org/web/20220113130051/" \
                   "https://example.com/",
      timestamp: ts,
    )
    expect(result).to be_available
    expect(result.url).to eq("example.com")
    expect(result.archive_url).to include("web.archive.org")
    expect(result.timestamp).to be_a(Archaeo::Timestamp)
  end

  it "reports unavailable when no archive exists" do
    result = described_class.new(url: "example.com",
                                 available: false)
    expect(result).not_to be_available
    expect(result.archive_url).to be_nil
    expect(result.timestamp).to be_nil
  end
end
