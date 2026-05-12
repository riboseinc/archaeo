# frozen_string_literal: true

module Archaeo
  # Detects and transcodes content from legacy encodings to UTF-8.
  #
  # Tries a configurable list of encodings in priority order,
  # returning the first that produces valid output. Used as a
  # fallback when Content-Type charset and HTML meta charset are
  # both absent.
  class EncodingDetector
    DEFAULT_ENCODINGS = [
      Encoding::UTF_8,
      Encoding::Windows_1251,
      Encoding::GB18030,
      Encoding::Shift_JIS,
      Encoding::EUC_KR,
      Encoding::ISO_8859_1,
      Encoding::Windows_1252,
    ].freeze

    BINARY_THRESHOLD = 0.1
    TEXT_CONTROL_BYTES = [0x09, 0x0A, 0x0D].freeze

    def initialize(encodings: DEFAULT_ENCODINGS)
      @encodings = encodings
    end

    def detect(bytes)
      return Encoding::UTF_8 if bytes.nil? || bytes.empty?

      string = bytes_to_string(bytes)

      @encodings.each do |enc|
        return enc if valid_in_encoding?(string, enc)
      end

      Encoding::UTF_8
    end

    def transcode(bytes, fallback: Encoding::UTF_8)
      return "" if bytes.nil? || bytes.empty?

      string = bytes.is_a?(String) ? bytes.dup : bytes.to_s
      return string if string.encoding == Encoding::UTF_8 && string.valid_encoding?

      binary = bytes_to_string(bytes)
      detected = detect(bytes)
      return binary.force_encoding(Encoding::UTF_8) if detected == Encoding::UTF_8

      encode_to_utf8(binary, detected, fallback)
    end

    def binary?(bytes)
      return false if bytes.nil? || bytes.empty?

      sample = bytes.byteslice(0, [bytes.bytesize, 4096].min)
      non_printable = sample.bytes.count do |b|
        b < 0x20 && !TEXT_CONTROL_BYTES.include?(b)
      end
      non_printable.to_f / sample.bytesize > BINARY_THRESHOLD
    end

    private

    def bytes_to_string(bytes)
      case bytes
      when String then bytes.dup.force_encoding(Encoding::ASCII_8BIT)
      else bytes.to_s.force_encoding(Encoding::ASCII_8BIT)
      end
    end

    def valid_in_encoding?(string, encoding)
      candidate = string.dup.force_encoding(encoding)
      candidate.valid_encoding?
    rescue StandardError
      false
    end

    def encode_to_utf8(string, source_encoding, fallback)
      candidate = string.dup.force_encoding(source_encoding)
      candidate.encode(Encoding::UTF_8,
                       invalid: :replace, undef: :replace,
                       replace: "?")
    rescue StandardError
      string.dup.force_encoding(fallback)
        .encode(Encoding::UTF_8,
                invalid: :replace, undef: :replace,
                replace: "?")
    end
  end
end
