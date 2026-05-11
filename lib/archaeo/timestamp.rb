# frozen_string_literal: true

require "date"

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
      freeze
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

    def to_iso8601
      @to_time.iso8601
    end

    def to_rfc3339
      @to_time.rfc3339
    end

    def +(seconds)
      self.class.from_time(@to_time + seconds)
    end

    def -(other)
      if other.is_a?(self.class)
        @to_time - other.to_time
      else
        self.class.from_time(@to_time - other)
      end
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

    def to_h
      { year: year, month: month, day: day,
        hour: hour, minute: minute, second: second }
    end

    def to_a
      [year, month, day, hour, minute, second]
    end

    def quarter
      ((month - 1) / 3) + 1
    end

    def wday
      @to_time.wday
    end

    def human_readable
      @to_time.strftime("%Y-%m-%d %H:%M:%S UTC")
    end

    def date_range(granularity = :day)
      start_ts = range_start(granularity)
      end_ts = range_end(start_ts, granularity)
      start_ts..end_ts
    end

    def inspect
      "#<#{self.class.name} #{self}>"
    end

    private

    def range_start(granularity)
      case granularity
      when :month then self.class.new(year: year, month: month)
      when :year then self.class.new(year: year)
      else self.class.new(year: year, month: month, day: day)
      end
    end

    def range_end(start_ts, granularity)
      case granularity
      when :month then next_month_start - 1
      when :year
        self.class.new(year: year, month: 12, day: 31,
                       hour: 23, minute: 59, second: 59)
      else start_ts + 86_399
      end
    end

    def next_month_start
      if month == 12
        self.class.new(year: year + 1, month: 1)
      else
        self.class.new(year: year, month: month + 1)
      end
    end
  end
end
