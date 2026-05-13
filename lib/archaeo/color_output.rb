# frozen_string_literal: true

module Archaeo
  # Minimal ANSI color helper for CLI output.
  #
  # Detects whether the output stream supports color and wraps
  # strings with escape codes accordingly. Respects --no-color
  # and TERM=dumb.
  class ColorOutput
    COLORS = {
      red: 31,
      green: 32,
      yellow: 33,
      blue: 34,
      magenta: 35,
      cyan: 36,
      white: 37,
    }.freeze

    STYLES = {
      bold: 1,
      dim: 2,
    }.freeze

    def initialize(enabled: nil, stream: $stderr)
      @enabled = enabled.nil? ? detect_color_support(stream) : enabled
    end

    COLORS.each do |name, code|
      define_method(name) do |text|
        colorize(text, code)
      end
    end

    STYLES.each do |name, code|
      define_method(name) do |text|
        colorize(text, code)
      end
    end

    def success(text)
      green(bold(text))
    end

    def warning(text)
      yellow(bold(text))
    end

    def error(text)
      red(bold(text))
    end

    def info(text)
      cyan(text)
    end

    private

    def colorize(text, code)
      return text unless @enabled

      "\e[#{code}m#{text}\e[0m"
    end

    def detect_color_support(stream)
      return false if stream.nil?
      return false if ENV["NO_COLOR"]
      return false if ENV["TERM"] == "dumb"

      stream.tty?
    end
  end
end
