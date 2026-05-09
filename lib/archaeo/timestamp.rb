# frozen_string_literal: true

module Archaeo
  # Value object representing a Wayback Machine timestamp (YYYYMMDDHHmmss).
  #
  # Supports parsing, formatting, comparison, and coercion from various
  # time representations.
  class Timestamp
    include Comparable

    FORMAT = "%Y%m%d%H%M%S"

    attr_reader :to_time

    def initialize(year:, month: 1, day: 1,
                   hour: 0, minute: 0, second: 0)
      @to_time = Time.utc(year, month, day, hour, minute, second)
    end

    def self.parse(string)
      year = string[0, 4].to_i
      month = string[4, 2].to_i if string.length >= 6
      day = string[6, 2].to_i if string.length >= 8

      new(year: year, month: month, day: day,
          **parse_time_parts(string))
    end

    def self.parse_time_parts(string)
      return {} if string.length < 10

      {
        hour: string[8, 2].to_i,
        minute: string[10, 2].to_i,
        second: string[12, 2].to_i,
      }
    end
    private_class_method :parse_time_parts

    def self.from_time(time)
      utc = time.getutc
      new(year: utc.year, month: utc.month, day: utc.day,
          hour: utc.hour, minute: utc.min, second: utc.sec)
    end

    def self.now
      from_time(Time.now)
    end

    def self.coerce(value)
      case value
      when Timestamp then value
      when String then parse(value)
      when Time then from_time(value)
      else
        raise ArgumentError,
              "Cannot coerce #{value.class} to Archaeo::Timestamp"
      end
    end

    def to_s
      @to_time.strftime(FORMAT)
    end

    def to_date
      Date.new(year, month, day)
    end

    def to_i
      @to_time.to_i
    end

    def <=>(other)
      return nil unless other.is_a?(self.class)

      to_s <=> other.to_s
    end

    def hash
      to_s.hash
    end

    def eql?(other)
      self == other
    end

    def year
      @to_time.year
    end

    def month
      @to_time.month
    end

    def day
      @to_time.day
    end

    def hour
      @to_time.hour
    end

    def minute
      @to_time.min
    end

    def second
      @to_time.sec
    end
  end
end
