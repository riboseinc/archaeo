# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::Cli do
  subject(:cli) { described_class.new }

  describe "version" do
    it "shows the version" do
      expect { described_class.start(%w[version]) }
        .to output(/archaeo #{Archaeo::VERSION}/o).to_stdout
    end

    it "shows version with --version flag" do
      expect { described_class.start(%w[--version]) }
        .to output(/archaeo #{Archaeo::VERSION}/o).to_stdout
    end
  end

  describe "snapshots" do
    it "lists snapshots for a URL" do
      header = Archaeo::CdxApi::ALL_FIELDS
      rows = [
        ["com,example)/", "20220113130051",
         "https://example.com/", "text/html",
         "200", "ABC", "12345"],
      ]
      body = JSON.generate([header] + rows)
      responses = [
        FakeHttpClient.response(status: 200, body: body),
      ]

      cdx = Archaeo::CdxApi.new(
        client: FakeHttpClient.new(responses),
      )
      allow(Archaeo::CdxApi).to receive(:new).and_return(cdx)

      expect { cli.snapshots("example.com") }
        .to output(/20220113130051.*200.*example.com/).to_stdout
    end

    it "outputs JSON format" do
      header = Archaeo::CdxApi::ALL_FIELDS
      rows = [
        ["com,example)/", "20220113130051",
         "https://example.com/", "text/html",
         "200", "ABC", "12345"],
      ]
      body = JSON.generate([header] + rows)
      responses = [
        FakeHttpClient.response(status: 200, body: body),
      ]

      cdx = Archaeo::CdxApi.new(
        client: FakeHttpClient.new(responses),
      )
      allow(Archaeo::CdxApi).to receive(:new).and_return(cdx)

      expect { described_class.start(%w[snapshots --format json example.com]) }
        .to output(/"timestamp"/).to_stdout
    end
  end

  describe "near" do
    it "finds the closest snapshot" do
      header = Archaeo::CdxApi::ALL_FIELDS
      rows = [
        ["com,example)/", "20220113130051",
         "https://example.com/", "text/html",
         "200", "ABC", "12345"],
      ]
      body = JSON.generate([header] + rows)
      responses = [
        FakeHttpClient.response(status: 200, body: body),
      ]

      cdx = Archaeo::CdxApi.new(
        client: FakeHttpClient.new(responses),
      )
      allow(Archaeo::CdxApi).to receive(:new).and_return(cdx)

      expect { cli.near("example.com", "20220101") }
        .to output(%r{web\.archive\.org}).to_stdout
    end
  end

  describe "available" do
    context "when archive exists" do
      before do
        body = JSON.generate({
                               "url" => "example.com",
                               "archived_snapshots" => {
                                 "closest" => {
                                   "url" => "https://web.archive.org/web/" \
                                            "20220113130051/https://example.com/",
                                   "timestamp" => "20220113130051",
                                   "status" => "200",
                                   "available" => true,
                                 },
                               },
                             })
        @responses = [
          FakeHttpClient.response(status: 200, body: body),
        ]

        api = Archaeo::AvailabilityApi.new(
          client: FakeHttpClient.new(@responses),
        )
        allow(Archaeo::AvailabilityApi).to receive(:new)
          .and_return(api)
      end

      it "reports availability" do
        expect { cli.available("example.com") }
          .to output(/Available.*web\.archive\.org/).to_stdout
      end
    end

    context "when no archive exists" do
      before do
        body = JSON.generate({
                               "url" => "example.com",
                               "archived_snapshots" => {},
                             })
        @responses = [
          FakeHttpClient.response(status: 200, body: body),
        ]

        api = Archaeo::AvailabilityApi.new(
          client: FakeHttpClient.new(@responses),
        )
        allow(Archaeo::AvailabilityApi).to receive(:new)
          .and_return(api)
      end

      it "exits with code 1" do
        expect { cli.available("example.com") }
          .to output(/Not available/).to_stdout
          .and raise_error(SystemExit) do |error|
            expect(error.status).to eq(1)
          end
      end
    end
  end

  describe "save" do
    it "saves a URL and reports the result" do
      now = Time.now.utc.strftime("%Y%m%d%H%M%S")
      responses = [
        FakeHttpClient.response(
          status: 200,
          headers: {
            "content-location" =>
              "/web/#{now}/https://example.com/",
          },
        ),
      ]

      api = Archaeo::SaveApi.new(
        client: FakeHttpClient.new(responses),
      )
      allow(Archaeo::SaveApi).to receive(:new).and_return(api)

      expect { cli.save("https://example.com/") }
        .to output(/Saved.*web\.archive\.org/).to_stdout
    end
  end

  describe "fetch" do
    it "fetches and outputs archived content" do
      responses = [
        FakeHttpClient.response(
          status: 200,
          headers: { "content-type" => "text/html" },
          body: "<html>Hello</html>",
        ),
      ]

      fetcher = Archaeo::Fetcher.new(
        client: FakeHttpClient.new(responses),
      )
      allow(Archaeo::Fetcher).to receive(:new).and_return(fetcher)

      expect { cli.fetch("https://example.com/", "20220615120000") }
        .to output("<html>Hello</html>").to_stdout
    end
  end

  describe "download" do
    it "downloads snapshots to output directory" do
      tmpdir = Dir.mktmpdir
      begin
        header = Archaeo::CdxApi::ALL_FIELDS
        rows = [
          ["com,example)/", "20220113130051",
           "https://example.com/", "text/html",
           "200", "ABC", "12345"],
        ]
        cdx_body = JSON.generate([header] + rows)
        fetch_body = "<html>archived</html>"
        responses = [
          FakeHttpClient.response(status: 200, body: cdx_body),
          FakeHttpClient.response(
            status: 200,
            headers: { "content-type" => "text/html" },
            body: fetch_body,
          ),
        ]
        fake = FakeHttpClient.new(responses)
        cdx = Archaeo::CdxApi.new(client: fake)
        allow(Archaeo::CdxApi).to receive(:new).and_return(cdx)

        downloader = Archaeo::BulkDownloader.new(
          client: fake, output_dir: tmpdir,
        )
        allow(Archaeo::BulkDownloader).to receive(:new)
          .and_return(downloader)

        expect do
          described_class.start(
            %W[download --output #{tmpdir} example.com],
          )
        end.to output.to_stderr

        files = Dir.glob(File.join(tmpdir, "**", "*.html"))
        expect(files.length).to eq(1)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  describe "known_urls command" do
    it "lists known URLs for a domain" do
      header = Archaeo::CdxApi::ALL_FIELDS
      rows = [
        ["com,example)/", "20220113130051",
         "https://example.com/", "text/html",
         "200", "ABC", "12345"],
      ]
      body = JSON.generate([header] + rows)
      responses = [
        FakeHttpClient.response(status: 200, body: body),
      ]

      cdx = Archaeo::CdxApi.new(
        client: FakeHttpClient.new(responses),
      )
      allow(Archaeo::CdxApi).to receive(:new).and_return(cdx)

      expect { described_class.start(%w[known_urls example.com]) }
        .to output(/example.com/).to_stdout
    end
  end

  describe "fetch with --output" do
    it "writes fetched content to a file" do
      tmpdir = Dir.mktmpdir
      begin
        outfile = File.join(tmpdir, "page.html")
        responses = [
          FakeHttpClient.response(
            status: 200,
            headers: { "content-type" => "text/html" },
            body: "<html>saved</html>",
          ),
        ]

        fetcher = Archaeo::Fetcher.new(
          client: FakeHttpClient.new(responses),
        )
        allow(Archaeo::Fetcher).to receive(:new).and_return(fetcher)

        expect do
          described_class.start(
            %W[fetch --output #{outfile} https://example.com/ 20220615120000],
          )
        end.to output.to_stderr

        expect(File.read(outfile)).to eq("<html>saved</html>")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  describe "snapshots --format csv" do
    it "outputs CSV format" do
      header = Archaeo::CdxApi::ALL_FIELDS
      rows = [
        ["com,example)/", "20220113130051",
         "https://example.com/", "text/html",
         "200", "ABC", "12345"],
      ]
      body = JSON.generate([header] + rows)
      responses = [
        FakeHttpClient.response(status: 200, body: body),
      ]

      cdx = Archaeo::CdxApi.new(
        client: FakeHttpClient.new(responses),
      )
      allow(Archaeo::CdxApi).to receive(:new).and_return(cdx)

      expect do
        described_class.start(%w[snapshots --format csv example.com])
      end.to output(/timestamp/).to_stdout
    end
  end

  describe "help" do
    it "shows help for snapshots command" do
      expect { described_class.start(%w[help snapshots]) }
        .to output(/List archived snapshots/).to_stdout
    end

    it "shows help for save command" do
      expect { described_class.start(%w[help save]) }
        .to output(/Save a URL/).to_stdout
    end

    it "shows help for download command" do
      expect { described_class.start(%w[help download]) }
        .to output(/Download all archived snapshots/).to_stdout
    end

    it "shows help for known_urls command" do
      expect { described_class.start(%w[help known_urls]) }
        .to output(/List all known URLs/).to_stdout
    end

    it "shows help for num_pages command" do
      expect { described_class.start(%w[help num_pages]) }
        .to output(/number of CDX result pages/).to_stdout
    end
  end

  describe "num_pages" do
    it "outputs the page count" do
      response = FakeHttpClient.response(status: 200, body: "7")
      fake = FakeHttpClient.new([response])
      cdx = Archaeo::CdxApi.new(client: fake)
      allow(Archaeo::CdxApi).to receive(:new).and_return(cdx)

      expect { described_class.start(%w[num_pages example.com]) }
        .to output("7\n").to_stdout
    end
  end
end
