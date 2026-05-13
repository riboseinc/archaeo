# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::Page, "#microposts" do
  def build_page(html)
    Archaeo::Page.new(
      content: html,
      content_type: "text/html",
      status_code: 200,
      archive_url: "https://web.archive.org/web/20220615000000/https://example.com/",
      original_url: "https://example.com/",
      timestamp: "20220615000000",
    )
  end

  it "extracts microposts from article elements" do
    page = build_page(<<~HTML)
      <html><body>
        <article>
          <h2>First Post</h2>
          <time datetime="2022-06-01">June 1</time>
          <p>This is the first article content.</p>
          <p>It has multiple paragraphs.</p>
        </article>
      </body></html>
    HTML

    posts = page.microposts
    expect(posts.size).to eq(1)
    expect(posts[0][:title]).to eq("First Post")
    expect(posts[0][:body]).to include("first article content")
    expect(posts[0][:date]).to eq("2022-06-01")
  end

  it "extracts author when present" do
    page = build_page(<<~HTML)
      <html><body>
        <article>
          <h2>Post Title</h2>
          <span class="author">Jane Doe</span>
          <p>Article body text here.</p>
        </article>
      </body></html>
    HTML

    posts = page.microposts
    expect(posts[0][:author]).to eq("Jane Doe")
  end

  it "extracts multiple microposts" do
    page = build_page(<<~HTML)
      <html><body>
        <article>
          <h2>Post One</h2>
          <p>Content one.</p>
        </article>
        <article>
          <h2>Post Two</h2>
          <p>Content two.</p>
        </article>
      </body></html>
    HTML

    posts = page.microposts
    expect(posts.size).to eq(2)
    expect(posts[0][:title]).to eq("Post One")
    expect(posts[1][:title]).to eq("Post Two")
  end

  it "extracts from role=article" do
    page = build_page(<<~HTML)
      <html><body>
        <div role="article">
          <h2>ARIA Article</h2>
          <p>Body text.</p>
        </div>
      </body></html>
    HTML

    posts = page.microposts
    expect(posts.size).to eq(1)
    expect(posts[0][:title]).to eq("ARIA Article")
  end

  it "extracts from common blog post classes" do
    page = build_page(<<~HTML)
      <html><body>
        <div class="post">
          <h2>Blog Post</h2>
          <p>Blog content here.</p>
        </div>
      </body></html>
    HTML

    posts = page.microposts
    expect(posts.size).to eq(1)
    expect(posts[0][:title]).to eq("Blog Post")
  end

  it "falls back to body when no article containers found" do
    page = build_page(<<~HTML)
      <html><body>
        <h1>Page Title</h1>
        <p>Some body text content here.</p>
        <p>Another paragraph with text.</p>
      </body></html>
    HTML

    posts = page.microposts
    expect(posts.size).to eq(1)
    expect(posts[0][:body]).to include("body text content")
  end

  it "returns empty array for non-HTML pages" do
    page = described_class.new(
      content: '{"key": "value"}',
      content_type: "application/json",
      status_code: 200,
      archive_url: "https://web.archive.org/web/20220615/https://example.com/api",
      original_url: "https://example.com/api",
      timestamp: "20220615000000",
    )

    expect(page.microposts).to eq([])
  end

  it "skips containers with no paragraph text" do
    page = build_page(<<~HTML)
      <html><body>
        <article>
          <img src="photo.jpg" alt="just an image" />
        </article>
      </body></html>
    HTML

    expect(page.microposts).to eq([])
  end

  it "extracts date from time element with datetime attribute" do
    page = build_page(<<~HTML)
      <html><body>
        <article>
          <h2>Dated Post</h2>
          <time datetime="2022-06-15T10:30:00Z">June 15</time>
          <p>Content here.</p>
        </article>
      </body></html>
    HTML

    posts = page.microposts
    expect(posts[0][:date]).to eq("2022-06-15T10:30:00Z")
  end

  it "extracts date from class-based date elements" do
    page = build_page(<<~HTML)
      <html><body>
        <article>
          <h2>Post</h2>
          <span class="post-date">2022-06-15</span>
          <p>Content here.</p>
        </article>
      </body></html>
    HTML

    posts = page.microposts
    expect(posts[0][:date]).to eq("2022-06-15")
  end
end
