# frozen_string_literal: true

require "json"
require "uri"

module Archaeo
  # Client for the Wayback Machine CDX Server API.
  #
  # Query archived snapshots by URL, timestamp range, filters,
  # and more. Returns Snapshot objects for each matching CDX record.
  class CdxApi
    ENDPOINT = "https://web.archive.org/cdx/search/cdx"

    ALL_FIELDS = %w[
      urlkey timestamp original
      mimetype statuscode digest length
    ].freeze

    MATCH_TYPES = %w[exact prefix host domain].freeze
    SORT_ORDERS = %w[default closest reverse].freeze
    DEFAULT_LIMIT = 25_000

    SCALAR_PARAMS = {
      from: "from",
      to: "to",
      match_type: "matchType",
      sort: "sort",
      limit: "limit",
      closest: "closest",
    }.freeze

    def initialize(client: HttpClient.new)
      @client = client
    end

    def snapshots(url, **options)
      validate_options!(options)

      Enumerator.new do |yielder|
        fetch_snapshots(url, options, yielder)
      end
    end

    def near(url, timestamp:)
      ts = Timestamp.coerce(timestamp)
      result = snapshots(url, sort: "closest",
                              closest: ts.to_s, limit: 1).first
      result || raise(NoSnapshotFound,
                      "No snapshot found near #{ts} for #{url}")
    end

    def oldest(url)
      near(url, timestamp: Timestamp.new(year: 1994, month: 1, day: 1))
    end

    def newest(url)
      near(url, timestamp: Timestamp.now)
    end

    def before(url, timestamp:)
      ts = Timestamp.coerce(timestamp)
      snapshots(url, sort: "closest", closest: ts.to_s).each do |snap|
        return snap if snap.timestamp < ts
      end
      raise NoSnapshotFound,
            "No snapshot found before #{ts} for #{url}"
    end

    def after(url, timestamp:)
      ts = Timestamp.coerce(timestamp)
      snapshots(url, sort: "closest", closest: ts.to_s).each do |snap|
        return snap if snap.timestamp > ts
      end
      raise NoSnapshotFound,
            "No snapshot found after #{ts} for #{url}"
    end

    private

    def fetch_snapshots(url, options, yielder)
      params = build_params(url, options)
      response = @client.get(
        "#{ENDPOINT}?#{URI.encode_www_form(params)}",
      )
      unless response.status == 200
        raise Error, "CDX API returned HTTP #{response.status}"
      end
      return if response.body.nil? || response.body.strip.empty?

      parse_cdx_json(response.body, yielder)
    end

    def validate_options!(options)
      validate_match_type!(options[:match_type])
      validate_sort!(options[:sort])
    end

    def validate_match_type!(type)
      return if type.nil? || MATCH_TYPES.include?(type.to_s)

      raise ArgumentError,
            "Invalid match_type: #{type}. " \
            "Use: #{MATCH_TYPES.join(', ')}"
    end

    def validate_sort!(sort)
      return if sort.nil? || SORT_ORDERS.include?(sort.to_s)

      raise ArgumentError,
            "Invalid sort: #{sort}. Use: #{SORT_ORDERS.join(', ')}"
    end

    def build_params(url, options)
      {
        "url" => url,
        "output" => "json",
        "fl" => ALL_FIELDS.join(","),
        "gzip" => options.fetch(:gzip, true) ? "true" : "false",
      }.tap do |params|
        merge_scalar_params!(params, options)
        merge_array_params!(params, options[:filters], "filter")
        merge_array_params!(params, options[:collapse], "collapse")
      end
    end

    def merge_scalar_params!(params, options)
      SCALAR_PARAMS.each do |key, api_key|
        value = options[key]
        params[api_key] = value.to_s if value
      end
    end

    def merge_array_params!(params, values, prefix)
      Array(values).each_with_index do |v, i|
        params["#{prefix}#{i}"] = v
      end
    end

    def parse_cdx_json(body, yielder)
      json = JSON.parse(body)
      return unless json.is_a?(Array) && json.length > 1

      header, *rows = json
      field_map = header.each_with_index.to_h
      rows.each { |row| yielder << build_snapshot(field_map, row) }
    end

    def build_snapshot(field_map, row)
      fetch = ->(f) { row[field_map[f]] if field_map[f] }

      Snapshot.new(
        urlkey: fetch.call("urlkey"),
        timestamp: fetch.call("timestamp"),
        original_url: fetch.call("original"),
        mimetype: fetch.call("mimetype"),
        status_code: fetch.call("statuscode"),
        digest: fetch.call("digest"),
        length: fetch.call("length"),
      )
    end
  end
end
