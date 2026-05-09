# frozen_string_literal: true

require "json"
require "uri"

module Archaeo
  # Client for the Wayback Machine CDX Server API.
  #
  # Supports all CDX features: field selection, filtering with regex,
  # collapsing, resume-key pagination, page-based pagination,
  # closest timestamp match, resolve revisits, and counters.
  #
  # @see https://github.com/internetarchive/wayback/tree/master/wayback-cdx-server
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
      offset: "offset",
      page: "page",
      page_size: "pageSize",
      fast_latest: "fastLatest",
      resolve_revisits: "resolveRevisits",
      show_dupe_count: "showDupeCount",
      show_skip_count: "showSkipCount",
      last_skip_timestamp: "lastSkipTimestamp",
    }.freeze

    def initialize(client: HttpClient.new)
      @client = client
    end

    # Returns an Enumerator of Snapshot objects, auto-paginating
    # via resume key unless an explicit page is requested.
    def snapshots(url, **options)
      url = UrlNormalizer.normalize(url)
      validate_options!(options)

      Enumerator.new do |yielder|
        if options.key?(:page)
          fetch_page(url, options, yielder)
        else
          fetch_with_resume_key(url, options, yielder)
        end
      end
    end

    def near(url, timestamp:)
      url = UrlNormalizer.normalize(url)
      ts = Timestamp.coerce(timestamp)
      result = snapshots(url, sort: "closest",
                              closest: ts.to_s, limit: 1).first
      if result&.blocked?
        raise BlockedSiteError,
              "Site is blocked: #{url}"
      end

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

    # Returns the number of pages for a paginated query.
    def num_pages(url, **options)
      url = UrlNormalizer.normalize(url)
      params = { "url" => url, "showNumPages" => "true" }
      merge_scalar_params!(params, options)
      response = @client.get(
        "#{ENDPOINT}?#{URI.encode_www_form(params)}",
      )
      unless response.status == 200
        raise Error,
              "CDX API returned HTTP #{response.status}"
      end

      response.body.strip.to_i
    end

    # Returns all unique original URLs under a domain.
    def known_urls(domain, match_type: "domain")
      domain = UrlNormalizer.normalize(domain)
      snapshots(domain, match_type: match_type,
                        collapse: ["urlkey"]).map(&:original_url).uniq
    end

    private

    def fetch_with_resume_key(url, options, yielder)
      params = build_params(url, options)
      loop do
        response = cdx_get(params)
        return if response.body.nil? || response.body.strip.empty?

        resume_key = parse_cdx_json(response.body, yielder)
        break if resume_key.nil? || resume_key.empty?

        params = params.merge("resumeKey" => resume_key)
      end
    end

    def fetch_page(url, options, yielder)
      params = build_params(url, options)
      response = cdx_get(params)
      return if response.body.nil? || response.body.strip.empty?

      parse_cdx_json(response.body, yielder)
    end

    def cdx_get(params)
      response = @client.get(
        "#{ENDPOINT}?#{URI.encode_www_form(params)}",
      )
      return response if response.status == 200

      if response.status == 503
        raise RateLimitError,
              "CDX API rate limited (HTTP 503)"
      end

      raise Error, "CDX API returned HTTP #{response.status}"
    end

    def validate_options!(options)
      validate_match_type!(options[:match_type])
      validate_sort!(options[:sort])
      validate_filters!(options[:filters])
      validate_collapses!(options[:collapse])
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

    def validate_filters!(filters)
      Array(filters).each { |f| CdxFilter.new(f) }
    end

    def validate_collapses!(collapses)
      Array(collapses).each do |c|
        field = c.to_s.split(":").first
        next if CdxFilter::VALID_FIELDS.include?(field)

        raise ArgumentError,
              "Invalid collapse field: #{field}. " \
              "Valid fields: #{CdxFilter::VALID_FIELDS.join(', ')}"
      end
    end

    def build_params(url, options)
      {
        "url" => url,
        "output" => "json",
        "fl" => ALL_FIELDS.join(","),
        "showResumeKey" => "true",
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
        next if value.nil?

        params[api_key] = value.to_s
      end
    end

    def merge_array_params!(params, values, prefix)
      Array(values).each_with_index do |v, i|
        params["#{prefix}#{i}"] = v.to_s
      end
    end

    # Parses CDX JSON response, handling the resume key trailer.
    #
    # JSON resume key format:
    #   [header, row1, row2, ..., [], ["resume_key_value"]]
    def parse_cdx_json(body, yielder)
      json = JSON.parse(body)
      return nil unless json.is_a?(Array) && json.length > 1

      json, resume_key = extract_resume_key(json)

      header = json[0]
      field_map = header.each_with_index.to_h
      json[1..].each do |row|
        next unless row.is_a?(Array) && !row.empty?

        yielder << build_snapshot(field_map, row)
      end

      resume_key
    end

    def extract_resume_key(json)
      last = json.last
      return [json, nil] unless last.is_a?(Array) && last.length == 1

      remaining = json[0..-2]
      if remaining.last.is_a?(Array) && remaining.last.empty?
        remaining = remaining[0..-2]
      end
      [remaining, last[0].to_s]
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
