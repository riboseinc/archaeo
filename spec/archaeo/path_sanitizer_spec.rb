# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Archaeo::PathSanitizer do
  let(:sanitizer) { described_class.new }

  describe "#sanitize" do
    it "strips scheme" do
      expect(sanitizer.sanitize("https://example.com/path"))
        .to eq("example.com/path")
    end

    it "recursively decodes percent-encoded characters" do
      expect(sanitizer.sanitize("https://example.com/blog%252Fpost"))
        .to eq("example.com/blog/post")
    end

    it "hashes query strings" do
      result = sanitizer.sanitize("https://example.com/page?a=1&b=2")
      expect(result).to start_with("example.com/page_")
      expect(result.length - "example.com/page_".length).to eq(8)
    end

    it "handles paths without query strings" do
      expect(sanitizer.sanitize("https://example.com/about"))
        .to eq("example.com/about")
    end

    it "replaces invalid characters" do
      result = sanitizer.sanitize("https://example.com/path<bad>")
      expect(result).to eq("example.com/path_bad_")
    end

    it "truncates long segments" do
      long_seg = "a" * 300
      result = sanitizer.sanitize("https://example.com/#{long_seg}")
      segments = result.split("/")
      expect(segments.last.length).to eq(200)
    end

    it "handles nested paths" do
      result = sanitizer.sanitize("https://example.com/a/b/c.html")
      expect(result).to eq("example.com/a/b/c.html")
    end
  end

  describe "#file_id" do
    it "strips archive prefix" do
      url = "https://web.archive.org/web/20220615/https://example.com/page"
      expect(sanitizer.file_id(url)).to eq("example.com/page")
    end

    it "strips identity prefix" do
      url = "https://web.archive.org/web/20220615id_/https://example.com/x"
      expect(sanitizer.file_id(url)).to eq("example.com/x")
    end
  end

  describe "#segment_for" do
    it "replaces invalid characters" do
      expect(sanitizer.segment_for('file"name')).to eq("file_name")
    end

    it "truncates long segments" do
      long = "x" * 300
      expect(sanitizer.segment_for(long).length).to eq(200)
    end

    it "preserves normal segments" do
      expect(sanitizer.segment_for("normal-file.txt")).to eq("normal-file.txt")
    end
  end
end

RSpec.describe Archaeo::PathConflictResolver do
  let(:tmpdir) { Dir.mktmpdir("archaeo-test") }
  let(:resolver) { described_class.new(tmpdir) }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#resolve" do
    it "resolves file blocking directory creation" do
      file_path = File.join(tmpdir, "blog")
      FileUtils.touch(file_path)
      paths = [file_path, File.join(tmpdir, "blog", "post.html")]
      resolver.resolve(paths)
      expect(File.directory?(file_path)).to be true
      expect(Dir.glob(File.join(tmpdir, "blog", "index*")).size).to eq(1)
    end

    it "does nothing when no conflicts exist" do
      file_path = File.join(tmpdir, "about.html")
      FileUtils.touch(file_path)
      paths = [file_path, File.join(tmpdir, "contact.html")]
      resolver.resolve(paths)
      expect(File.file?(file_path)).to be true
    end
  end
end
