# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo do
  it "has a version number" do
    expect(Archaeo::VERSION).not_to be_nil
  end

  it "defines error classes" do
    expect(Archaeo::Error).to be < StandardError
    expect(Archaeo::NoSnapshotFound).to be < Archaeo::Error
    expect(Archaeo::BlockedSiteError).to be < Archaeo::Error
    expect(Archaeo::RateLimitError).to be < Archaeo::Error
    expect(Archaeo::MaximumRetriesExceeded).to be < Archaeo::Error
    expect(Archaeo::ArchiveNotAvailable).to be < Archaeo::Error
    expect(Archaeo::InvalidResponse).to be < Archaeo::Error
    expect(Archaeo::SaveFailed).to be < Archaeo::Error
  end

  it "autoloads all major classes" do
    expect(Archaeo::Timestamp).to be_a(Class)
    expect(Archaeo::ArchiveUrl).to be_a(Class)
    expect(Archaeo::Snapshot).to be_a(Class)
    expect(Archaeo::Page).to be_a(Class)
    expect(Archaeo::SaveResult).to be_a(Class)
    expect(Archaeo::AvailabilityResult).to be_a(Class)
    expect(Archaeo::HttpClient).to be_a(Class)
    expect(Archaeo::CdxApi).to be_a(Class)
    expect(Archaeo::AvailabilityApi).to be_a(Class)
    expect(Archaeo::SaveApi).to be_a(Class)
    expect(Archaeo::Fetcher).to be_a(Class)
  end
end
