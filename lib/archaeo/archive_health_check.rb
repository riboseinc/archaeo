# frozen_string_literal: true

module Archaeo
  # Verifies that archived snapshots are still accessible.
  #
  # Checks each snapshot by performing HEAD requests to the
  # archive URL and reporting accessibility status.
  HealthReport = Struct.new(
    :total, :accessible, :missing, :errors, :details,
    keyword_init: true
  )

  HealthDetail = Struct.new(
    :snapshot, :status, :error,
    keyword_init: true
  )

  class ArchiveHealthCheck
    def initialize(client: HttpClient.new, cdx_api: nil)
      @client = client
      @cdx_api = cdx_api
    end

    def check(url, from: nil, to: nil, sample: nil)
      snapshots = fetch_snapshots(url, from: from, to: to)
      snapshots = sample_snapshots(snapshots, sample) if sample

      details = check_snapshots(snapshots)
      build_report(details)
    end

    private

    def fetch_snapshots(url, from:, to:)
      cdx = @cdx_api || CdxApi.new(client: @client)
      opts = {}
      opts[:from] = from if from
      opts[:to] = to if to
      cdx.snapshots(url, **opts)
        .select(&:success?).to_a
    end

    def sample_snapshots(snapshots, count)
      return snapshots if count.nil? || count >= snapshots.size

      step = snapshots.size.to_f / count
      (0...count).map { |i| snapshots[(i * step).to_i] }
    end

    def check_snapshots(snapshots)
      snapshots.map do |snap|
        check_single(snap)
      end
    end

    def check_single(snapshot)
      response = @client.head(snapshot.archive_url)
      status = response.status.between?(200, 399) ? :accessible : :missing
      HealthDetail.new(snapshot: snapshot, status: status, error: nil)
    rescue StandardError => e
      HealthDetail.new(snapshot: snapshot, status: :error, error: e.message)
    end

    def build_report(details)
      total = details.size
      accessible = details.count { |d| d.status == :accessible }
      missing = details.count { |d| d.status == :missing }
      errors = details.count { |d| d.status == :error }

      HealthReport.new(
        total: total, accessible: accessible,
        missing: missing, errors: errors,
        details: details
      )
    end
  end
end
