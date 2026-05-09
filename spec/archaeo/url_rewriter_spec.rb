# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::UrlRewriter do
  subject(:rewriter) do
    described_class.new(
      "https://web.archive.org/web/20220615000000/",
      "local",
    )
  end

  describe "#rewrite" do
    it "rewrites archive URLs to local paths" do
      url = "https://web.archive.org/web/20220615000000/" \
            "https://example.com/style.css"
      expect(rewriter.rewrite(url))
        .to eq("local/https://example.com/style.css")
    end

    it "leaves non-archive URLs unchanged" do
      expect(rewriter.rewrite("https://cdn.example.com/style.css"))
        .to eq("https://cdn.example.com/style.css")
    end

    it "rewrites URLs with nested paths" do
      url = "https://web.archive.org/web/20220615000000/" \
            "https://example.com/assets/img/logo.png"
      expect(rewriter.rewrite(url))
        .to eq("local/https://example.com/assets/img/logo.png")
    end
  end
end
