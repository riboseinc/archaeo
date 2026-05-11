# frozen_string_literal: true

require "digest"

module Archaeo
  # Downloads archived content from the Wayback Machine.
  #
  # Constructs the appropriate archive URL, follows redirects,
  # and returns a Page model with content and metadata.
  class Fetcher
    MAX_REDIRECTS = 5
    BASE = "https://web.archive.org"

    def initialize(client: HttpClient.new)
      @client = client
    end

    def fetch(url, timestamp:, identity: false, snapshot: nil)
      url = UrlNormalizer.normalize(url)
      ts = Timestamp.coerce(timestamp)
      archive_url = ArchiveUrl.new(url, timestamp: ts,
                                        identity: identity)
      response = follow_redirects(archive_url.to_s)
      verify_integrity!(response, snapshot) if snapshot
      build_page(response, archive_url.to_s, url, ts)
    end

    def fetch!(url, timestamp:, identity: false, snapshot: nil)
      page = fetch(url, timestamp: timestamp, identity: identity,
                        snapshot: snapshot)
      return page if page.status_code.between?(200, 299)

      raise FetchError.new(
        "HTTP #{page.status_code} for #{page.original_url}",
        status_code: page.status_code,
        url: page.original_url,
        page: page,
      )
    end

    def fetch_page_with_assets(url, timestamp:)
      page = fetch(url, timestamp: timestamp)
      assets = AssetExtractor.new(page.content,
                                  base_url: page.archive_url).extract
      PageBundle.new(page: page, assets: assets)
    end

    private

    def verify_integrity!(response, snapshot)
      return unless snapshot.digest && !snapshot.digest.empty?

      expected = snapshot.digest.delete_prefix("SHA1-")
      actual = Digest::SHA1.hexdigest(response.body)
      return if expected == actual

      raise IntegrityError,
            "Digest mismatch for #{snapshot.original_url}: " \
            "expected #{expected}, got #{actual}"
    end

    def build_page(response, archive_url, url, timestamp)
      Page.new(
        content: response.body,
        content_type: response.headers["content-type"],
        status_code: response.status,
        archive_url: archive_url,
        original_url: url,
        timestamp: timestamp,
      )
    end

    def follow_redirects(url, remaining = MAX_REDIRECTS)
      raise Error, "Too many redirects for #{url}" if remaining.negative?

      response = @client.get(url)
      return response unless redirect?(response)

      new_url = resolve_redirect(url, response.headers["location"])
      follow_redirects(new_url, remaining - 1)
    end

    def redirect?(response)
      status = response.status
      location = response.headers["location"]
      status.between?(300, 399) && location
    end

    def resolve_redirect(current_url, location)
      return location if location.start_with?("http")
      return "#{BASE}#{location}" if location.start_with?("/web/")

      URI.join(current_url, location).to_s
    rescue URI::InvalidURIError
      location
    end
  end
end
