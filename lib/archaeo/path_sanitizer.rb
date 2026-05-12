# frozen_string_literal: true

require "digest"
require "uri"

module Archaeo
  # Sanitizes URLs into safe filesystem paths.
  #
  # Handles recursive percent-decoding, query string hashing,
  # segment truncation, and invalid character replacement.
  class PathSanitizer
    DEFAULT_MAX_SEGMENT = 200
    HASH_LENGTH = 8
    MAX_DECODE_ITERATIONS = 5

    INVALID_CHARS = /[<>:"|?*#]/
    SEPARATOR_RE = %r{[/\\]}

    attr_reader :max_segment_length

    def initialize(max_segment_length: DEFAULT_MAX_SEGMENT)
      @max_segment_length = max_segment_length
    end

    def sanitize(url)
      path = strip_scheme(url)
      path = recursive_decode(path)
      path = hash_query_strings(path)
      clean_segments(path)
    end

    def file_id(archive_url)
      stripped = strip_archive_prefix(archive_url)
      sanitize(stripped)
    end

    def segment_for(path_segment)
      cleaned = path_segment.gsub(INVALID_CHARS, "_")
      truncate(cleaned)
    end

    private

    def strip_scheme(url)
      url.to_s.sub(%r{\Ahttps?://}, "")
    end

    def strip_archive_prefix(url)
      url.to_s.sub(%r{\Ahttps?://web\.archive\.org/web/\d+(?:id_)?/}, "")
        .sub(%r{\Ahttps?://}, "")
    end

    def recursive_decode(str)
      MAX_DECODE_ITERATIONS.times do
        decoded = decode(str)
        return decoded if decoded == str

        str = decoded
      end
      str
    end

    def decode(str)
      URI.decode_www_form_component(str)
    rescue StandardError
      str
    end

    def hash_query_strings(path)
      return path unless path.include?("?")

      base, query = path.split("?", 2)
      hash = Digest::SHA256.hexdigest(query)[0, HASH_LENGTH]
      "#{base}_#{hash}"
    end

    def clean_segments(path)
      segments = path.split(SEPARATOR_RE).reject(&:empty?)
      return "" if segments.empty?

      segments.map do |seg|
        segment_for(seg)
      end.join(File::SEPARATOR)
    end

    def truncate(segment)
      return segment if segment.length <= @max_segment_length

      segment[0, @max_segment_length]
    end
  end

  # Resolves file/directory path conflicts in download targets.
  #
  # Detects when a file path would block creation of a needed directory
  # (or vice versa) and resolves by relocating the file.
  class PathConflictResolver
    def initialize(base_dir)
      @base_dir = base_dir
    end

    def resolve(paths)
      conflicts = detect_conflicts(paths)
      relocate_conflicts(conflicts)
      paths
    end

    def conflict?(file_path)
      return false if File.directory?(file_path)
      return false unless File.file?(file_path)

      File.exist?(file_path) && needs_directory_under?(file_path)
    end

    private

    def detect_conflicts(paths)
      conflicts = Set.new
      paths.each do |path|
        paths.each do |other|
          next if path == other

          prefix = path + File::SEPARATOR
          if other.start_with?(prefix) && File.file?(path)
            # `path` is a prefix of `other` — if `path` is a file, it blocks `other`
            conflicts << path
          end
        end
      end
      conflicts.to_a
    end

    def relocate_conflicts(conflicts)
      conflicts.each do |conflict_path|
        next unless File.file?(conflict_path)

        ext = File.extname(conflict_path)
        tmp_file = "#{conflict_path}.archaeo_tmp"
        FileUtils.mv(conflict_path, tmp_file)
        FileUtils.mkdir_p(conflict_path)
        new_file = File.join(conflict_path, "index#{ext}")
        FileUtils.mv(tmp_file, new_file)
      end
    end

    def needs_directory_under?(file_path)
      parent = File.dirname(file_path)
      children = Dir.glob("#{parent}/*")
      children.any? { |c| File.directory?(c) }
    end
  end
end
