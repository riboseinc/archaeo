# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Archaeo::LocalRewriter do
  let(:tmpdir) { Dir.mktmpdir }
  let(:output_dir) { File.join(tmpdir, "output") }

  after { FileUtils.rm_rf(tmpdir) }

  def write_input_file(name, content)
    path = File.join(tmpdir, "input", name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  it "rewrites HTML files with archive URLs" do
    write_input_file("page.html", <<~HTML)
      <html><body>
        <img src="https://web.archive.org/web/20220615/https://example.com/img.png" />
      </body></html>
    HTML

    rewriter = described_class.new(prefix: "local")
    summary = rewriter.rewrite_directory(
      File.join(tmpdir, "input"), output_dir
    )

    expect(summary.rewritten).to eq(1)
    expect(summary.total).to eq(1)
    output = File.read(File.join(output_dir, "page.html"))
    expect(output).not_to include("web.archive.org")
    expect(output).to include("local")
  end

  it "rewrites CSS files with archive URLs" do
    write_input_file("style.css", <<~CSS)
      .bg { background: url('https://web.archive.org/web/20220615/https://example.com/bg.png'); }
    CSS

    rewriter = described_class.new(prefix: "assets")
    summary = rewriter.rewrite_directory(
      File.join(tmpdir, "input"), output_dir
    )

    expect(summary.rewritten).to eq(1)
    output = File.read(File.join(output_dir, "style.css"))
    expect(output).not_to include("web.archive.org")
    expect(output).to include("assets")
  end

  it "rewrites JS files when rewrite_js is enabled" do
    write_input_file("app.js", <<~JS)
      var url = 'https://web.archive.org/web/20220615/https://example.com/api';
    JS

    rewriter = described_class.new(prefix: "local", rewrite_js: true)
    summary = rewriter.rewrite_directory(
      File.join(tmpdir, "input"), output_dir
    )

    expect(summary.rewritten).to eq(1)
    output = File.read(File.join(output_dir, "app.js"))
    expect(output).not_to include("web.archive.org")
  end

  it "skips files without archive URLs" do
    write_input_file("clean.html", "<html><body>Hello</body></html>")

    rewriter = described_class.new(prefix: "local")
    summary = rewriter.rewrite_directory(
      File.join(tmpdir, "input"), output_dir
    )

    expect(summary.skipped).to eq(1)
    expect(summary.rewritten).to eq(0)
  end

  it "skips binary files" do
    binary_path = File.join(tmpdir, "input", "image.png")
    FileUtils.mkdir_p(File.dirname(binary_path))
    File.binwrite(binary_path, "\x89PNG\r\n\x1a\n")

    rewriter = described_class.new(prefix: "local")
    summary = rewriter.rewrite_directory(
      File.join(tmpdir, "input"), output_dir
    )

    expect(summary.total).to eq(0)
  end

  it "handles nested directory structures" do
    write_input_file("sub/deep/page.html", <<~HTML)
      <html><body>
        <a href="https://web.archive.org/web/20220615/https://example.com/link">Link</a>
      </body></html>
    HTML

    rewriter = described_class.new(prefix: "local")
    summary = rewriter.rewrite_directory(
      File.join(tmpdir, "input"), output_dir
    )

    expect(summary.rewritten).to eq(1)
    output = File.read(File.join(output_dir, "sub/deep/page.html"))
    expect(output).not_to include("web.archive.org")
  end

  it "rewrites in-place when no output directory specified" do
    input_dir = File.join(tmpdir, "input")
    write_input_file("page.html", <<~HTML)
      <html><body>
        <img src="https://web.archive.org/web/20220615/https://example.com/img.png" />
      </body></html>
    HTML

    rewriter = described_class.new(prefix: "local")
    summary = rewriter.rewrite_directory(input_dir, input_dir)

    expect(summary.rewritten).to eq(1)
    output = File.read(File.join(input_dir, "page.html"))
    expect(output).not_to include("web.archive.org")
  end

  it "reports elapsed time" do
    write_input_file("page.html", <<~HTML)
      <html><body>
        <img src="https://web.archive.org/web/20220615/https://example.com/img.png" />
      </body></html>
    HTML

    rewriter = described_class.new(prefix: "local")
    summary = rewriter.rewrite_directory(
      File.join(tmpdir, "input"), output_dir
    )

    expect(summary.elapsed).to be >= 0
  end

  describe "#rewrite_file" do
    it "returns nil for files without archive URLs" do
      input = File.join(tmpdir, "clean.html")
      output = File.join(tmpdir, "out.html")
      File.write(input, "<html><body>Hello</body></html>")

      rewriter = described_class.new(prefix: "local")
      expect(rewriter.rewrite_file(input, output)).to be_nil
    end

    it "returns true for successfully rewritten files" do
      input = File.join(tmpdir, "page.html")
      output = File.join(tmpdir, "out.html")
      File.write(input, <<~HTML)
        <html><body>
          <img src="https://web.archive.org/web/20220615/https://example.com/img.png" />
        </body></html>
      HTML

      rewriter = described_class.new(prefix: "local")
      expect(rewriter.rewrite_file(input, output)).to be true
      expect(File.read(output)).to include("local")
    end
  end
end
