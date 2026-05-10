# frozen_string_literal: true

require "json"

module Archaeo
  # Categorized collection of asset URLs extracted from an archived page.
  #
  # Assets are grouped by type (css, js, image, font, media) for
  # convenient access during bulk download or local archiving.
  class AssetList
    include Enumerable

    CATEGORIES = %i[css js image font media].freeze

    def initialize
      @urls_by_type = {}
      CATEGORIES.each { |c| @urls_by_type[c] = [] }
    end

    def add(url, type:)
      return if url.nil? || url.empty?
      return if @urls_by_type[type].include?(url)

      @urls_by_type[type] << url
    end

    def each(&block)
      all.each(&block)
    end

    def css
      @urls_by_type[:css]
    end

    def js
      @urls_by_type[:js]
    end

    def images
      @urls_by_type[:image]
    end

    def fonts
      @urls_by_type[:font]
    end

    def media
      @urls_by_type[:media]
    end

    def all
      @urls_by_type.values.flatten.uniq
    end

    def size
      all.size
    end

    def empty?
      all.empty?
    end

    def to_h
      @urls_by_type.transform_values(&:dup)
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    def counts
      @urls_by_type.transform_values(&:size)
    end
  end
end
