# frozen_string_literal: true

require "digest"

module Archaeo
  # Compares two archived snapshots of the same URL.
  #
  # Produces text diffs, structural change analysis, link and
  # asset change tracking between snapshots at different timestamps.
  class SnapshotDiff
    attr_reader :url, :snapshot_a, :snapshot_b

    def initialize(url:, page_a:, page_b:, timestamp_a:, timestamp_b:)
      @url = url
      @page_a = page_a
      @page_b = page_b
      @timestamp_a = Timestamp.coerce(timestamp_a)
      @timestamp_b = Timestamp.coerce(timestamp_b)
    end

    def content_changed?
      content_digest(@page_a.content) != content_digest(@page_b.content)
    end

    def text_diff
      lines_a = @page_a.content.to_s.lines
      lines_b = @page_b.content.to_s.lines
      build_unified_diff(lines_a, lines_b)
    end

    def link_changes
      links_a = extract_links(@page_a)
      links_b = extract_links(@page_b)
      compute_set_diff(links_a, links_b)
    end

    def asset_changes
      assets_a = extract_assets(@page_a)
      assets_b = extract_assets(@page_b)
      compute_set_diff(assets_a, assets_b)
    end

    def structural_changes
      return {} unless @page_a.html? && @page_b.html?

      elements_a = count_elements(@page_a)
      elements_b = count_elements(@page_b)
      build_element_diff(elements_a, elements_b)
    end

    def to_h
      {
        url: @url,
        timestamp_a: @timestamp_a.to_s,
        timestamp_b: @timestamp_b.to_s,
        content_changed: content_changed?,
        links_added: link_changes[:added],
        links_removed: link_changes[:removed],
        assets_added: asset_changes[:added],
        assets_removed: asset_changes[:removed],
        structural_changes: structural_changes,
      }
    end

    def as_json(*)
      to_h
    end

    private

    def content_digest(content)
      Digest::SHA256.hexdigest(content.to_s)
    end

    def build_unified_diff(lines_a, lines_b)
      diff = []
      max_len = [lines_a.size, lines_b.size].max
      max_len.times do |i|
        la = lines_a[i]
        lb = lines_b[i]
        if la == lb
          diff << " #{la}"
        else
          diff << "- #{la}" if la
          diff << "+ #{lb}" if lb
        end
      end
      diff.join
    end

    def extract_links(page)
      return Set.new unless page.html?

      page.links.filter_map { |l| l[:href] }.to_set
    end

    def extract_assets(page)
      return Set.new unless page.html?

      extractor = AssetExtractor.new(page.content, base_url: page.archive_url)
      extractor.extract.all.to_set
    rescue StandardError
      Set.new
    end

    def count_elements(page)
      require "nokogiri"
      doc = Nokogiri::HTML(page.content)
      counts = Hash.new(0)
      doc.css("*").each { |el| counts[el.name] += 1 }
      counts
    end

    def compute_set_diff(set_a, set_b)
      {
        added: (set_b - set_a).to_a.sort,
        removed: (set_a - set_b).to_a.sort,
        unchanged: (set_a & set_b).size,
      }
    end

    def build_element_diff(counts_a, counts_b)
      all_tags = (counts_a.keys + counts_b.keys).uniq.sort
      changes = {}
      all_tags.each do |tag|
        ca = counts_a[tag]
        cb = counts_b[tag]
        next if ca == cb

        changes[tag] = { from: ca, to: cb }
      end
      changes
    end
  end
end
