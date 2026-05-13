# frozen_string_literal: true

require "digest"
require "time"
require "zlib"

module Archaeo
  # Reads WARC (Web ARChive) format files (.warc, .warc.gz).
  #
  # Parses WARC 1.0 records and yields WarcRecord value objects
  # containing headers and body content.
  class WarcReader
    WARC_VERSION = "WARC/1.0"
    CRLF = "\r\n"
    HEADER_END = "\r\n\r\n"

    def initialize
      @record_count = 0
    end

    def read(path, &block)
      io = open_warc(path)
      read_records_from_io(io, &block)
    ensure
      io&.close
    end

    def read_records(path)
      records = []
      read(path) { |record| records << record }
      records
    end

    private

    def open_warc(path)
      if path.end_with?(".gz")
        Zlib::GzipReader.open(path)
      else
        File.open(path, "rb")
      end
    end

    def read_records_from_io(io)
      buffer = +""
      loop do
        chunk = io.read(8192)
        buffer << chunk if chunk

        while (record = try_parse_record(buffer))
          yield record
        end

        break unless chunk
      end

      return if buffer.strip.empty?

      record = try_parse_record(buffer, final: true)
      yield record if record
    end

    def try_parse_record(buffer, final: false)
      header_end = buffer.index(HEADER_END)
      return nil unless header_end

      header_block = buffer.byteslice(0, header_end)
      headers = parse_warc_headers(header_block.split(CRLF))
      return nil unless headers[:warc_type]

      content_length = headers[:content_length].to_i
      body_start = header_end + HEADER_END.length
      body_end = body_start + content_length

      return nil unless final || buffer.bytesize >= body_end

      body = buffer.byteslice(body_start, content_length).to_s
      record = WarcRecord.new(
        version: headers.delete(:version),
        headers: headers,
        body: body,
      )

      total_consumed = body_end
      total_consumed += 2 while buffer.byteslice(total_consumed, 2) == CRLF

      remaining = buffer.byteslice(total_consumed,
                                   buffer.bytesize - total_consumed)
      buffer.replace(remaining.to_s)
      record
    end

    def parse_warc_headers(lines)
      headers = {}
      lines.each do |line|
        case line
        when /\AWARC\/(\d+\.\d+)\z/
          headers[:version] = $1
        when /\A([^:]+):\s*(.*)\z/
          key = $1.downcase.tr("-", "_").to_sym
          headers[key] = $2
        else
          break if line.strip.empty?
        end
      end
      headers
    end
  end

  # Writes snapshots to WARC format files (.warc, .warc.gz).
  #
  # Produces valid WARC 1.0 files with response and metadata records.
  class WarcWriter
    WARC_VERSION = "WARC/1.0"
    RECORD_SEP = "\r\n\r\n"
    CRLF = "\r\n"

    def initialize(software: "archaeo/#{VERSION}")
      @software = software
      @record_count = 0
    end

    def write(path, pages, compress: nil)
      compress = path.end_with?(".gz") if compress.nil?
      io = open_warc(path, compress)
      write_warcinfo(io, path)
      pages.each { |page| write_page(io, page) }
    ensure
      io&.close
    end

    private

    def open_warc(path, compress)
      if compress
        Zlib::GzipWriter.open(path)
      else
        File.open(path, "wb")
      end
    end

    def write_warcinfo(io, filename)
      fields = {
        software: @software,
        format: "WARC File Format 1.0",
        filename: File.basename(filename),
      }
      body = fields.map { |k, v| "#{k}: #{v}" }.join(CRLF) + CRLF
      record_id = generate_record_id
      headers = warc_headers(
        type: "warcinfo",
        record_id: record_id,
        date: Time.now.utc.iso8601,
        content_type: "application/warc-fields",
        content_length: body.bytesize,
      )
      io.write(headers + body + RECORD_SEP)
    end

    def write_page(io, page)
      record_id = generate_record_id
      date = page.timestamp.to_time.utc.iso8601

      http_headers = build_http_headers(page)
      body = page.content.to_s
      full_body = http_headers + body

      headers = warc_headers(
        type: "response",
        record_id: record_id,
        date: date,
        target_uri: page.original_url.to_s,
        content_type: "application/http;msgtype=response",
        content_length: full_body.bytesize,
      )

      io.write(headers + full_body + RECORD_SEP)
      @record_count += 1
    end

    def build_http_headers(page)
      parts = ["HTTP/1.1 #{page.status_code}"]
      parts << "Content-Type: #{page.content_type}"
      parts << "Content-Length: #{page.size}"
      parts.join(CRLF) + CRLF
    end

    def warc_headers(type:, record_id:, date:, target_uri: nil,
                     content_type: nil, content_length: 0)
      lines = [
        WARC_VERSION.to_s,
        "WARC-Type: #{type}",
        "WARC-Record-ID: #{record_id}",
        "WARC-Date: #{date}",
      ]
      lines << "WARC-Target-URI: #{target_uri}" if target_uri
      lines << "Content-Type: #{content_type}" if content_type
      lines << "Content-Length: #{content_length}"
      lines.join(CRLF) + RECORD_SEP
    end

    def generate_record_id
      @record_count += 1
      uuid = Digest::SHA256.hexdigest(
        "#{Time.now.utc.to_f}-#{@record_count}-#{rand(1 << 32)}",
      )
      "<urn:uuid:#{uuid[0, 8]}-#{uuid[8, 4]}-#{uuid[12, 4]}-" \
        "#{uuid[16, 4]}-#{uuid[20, 12]}>"
    end
  end

  # Value object representing a single WARC record.
  WarcRecord = Struct.new(
    :version, :headers, :body,
    keyword_init: true
  ) do
    def warc_type
      headers[:warc_type]
    end

    def target_uri
      headers[:warc_target_uri]
    end

    def date
      headers[:warc_date]
    end

    def content_type
      headers[:content_type]
    end

    def content_length
      headers[:content_length].to_i
    end

    def response?
      warc_type == "response"
    end

    def warcinfo?
      warc_type == "warcinfo"
    end

    def to_h
      { version: version, headers: headers, body_length: body.to_s.bytesize }
    end
  end
end
