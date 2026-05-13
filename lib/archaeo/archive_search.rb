# frozen_string_literal: true

module Archaeo
  # Value object for a single search match within an archived snapshot.
  SearchResult = Struct.new(
    :url, :snapshot, :context, :match_offset,
    keyword_init: true
  ) do
    def to_h
      {
        url: url,
        snapshot: snapshot.as_json,
        context: context,
        match_offset: match_offset,
      }
    end

    def as_json(*)
      to_h
    end
  end

  # Full-text search across archived snapshots.
  #
  # Fetches snapshots from CDX, downloads their content, and
  # searches for the given query string. Returns matches with
  # surrounding context for each hit.
  class ArchiveSearch
    CONTEXT_RADIUS = 80

    def initialize(cdx_api: CdxApi.new, fetcher: Fetcher.new)
      @cdx = cdx_api
      @fetcher = fetcher
    end

    def search(url, query:, from: nil, to: nil,
               max_results: nil, case_sensitive: false)
      if query.nil? || query.empty?
        raise ArgumentError,
              "query must not be empty"
      end

      url = UrlNormalizer.normalize(url)
      opts = build_options(from, to)

      snapshots = @cdx.snapshots(url, **opts)
        .select { |s| s.success? && s.mimetype.to_s.include?("text") }
        .to_a

      find_matches(snapshots, query, case_sensitive, max_results)
    end

    private

    def build_options(from, to)
      opts = { collapse: ["digest"] }
      opts[:from] = Timestamp.coerce(from).to_s if from
      opts[:to] = Timestamp.coerce(to).to_s if to
      opts
    end

    def find_matches(snapshots, query, case_sensitive, max_results)
      results = []
      pattern = build_pattern(query, case_sensitive)

      snapshots.each do |snap|
        break if max_results && results.size >= max_results

        content = fetch_content(snap)
        next unless content

        scan_content(content, pattern).each do |match_offset|
          results << SearchResult.new(
            url: snap.original_url,
            snapshot: snap,
            context: extract_context(content, match_offset, query.length),
            match_offset: match_offset,
          )
          break if max_results && results.size >= max_results
        end
      end

      results
    end

    def build_pattern(query, case_sensitive)
      escaped = Regexp.escape(query)
      return /#{escaped}/im unless case_sensitive

      /#{escaped}/m
    end

    def fetch_content(snapshot)
      page = @fetcher.fetch(
        snapshot.original_url, timestamp: snapshot.timestamp
      )
      page.content if page.text?
    rescue Error
      nil
    end

    def scan_content(content, pattern)
      offsets = []
      content.scan(pattern) do
        offsets << Regexp.last_match.offset(0).first
      end
      offsets
    end

    def extract_context(content, offset, length)
      start_pos = [0, offset - CONTEXT_RADIUS].max
      end_pos = [content.length, offset + length + CONTEXT_RADIUS].min

      ctx = content[start_pos...end_pos]
      ctx = "...#{ctx}" if start_pos.positive?
      ctx = "#{ctx}..." if end_pos < content.length
      ctx.tr("\n\r", " ").strip
    end
  end
end
