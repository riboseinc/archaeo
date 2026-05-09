# frozen_string_literal: true

require "spec_helper"

RSpec.describe Archaeo::Timestamp do
  describe ".new" do
    it "constructs from full date/time components" do
      ts = described_class.new(year: 2022, month: 1, day: 13, hour: 13,
                               minute: 0, second: 51)
      expect(ts.to_s).to eq("20220113130051")
    end

    it "defaults month, day, hour, minute, second to 1/1/0/0/0" do
      ts = described_class.new(year: 2020)
      expect(ts.to_s).to eq("20200101000000")
    end
  end

  describe ".parse" do
    it "parses a 14-digit Wayback timestamp" do
      ts = described_class.parse("20220113130051")
      expect(ts.year).to eq(2022)
      expect(ts.month).to eq(1)
      expect(ts.day).to eq(13)
      expect(ts.hour).to eq(13)
      expect(ts.minute).to eq(0)
      expect(ts.second).to eq(51)
    end

    it "parses the minimum timestamp" do
      ts = described_class.parse("19940101000000")
      expect(ts.year).to eq(1994)
    end

    it "parses a 4-digit year-only timestamp" do
      ts = described_class.parse("2022")
      expect(ts.year).to eq(2022)
      expect(ts.to_s).to eq("20220101000000")
    end

    it "parses an 8-digit date timestamp" do
      ts = described_class.parse("20220615")
      expect(ts.year).to eq(2022)
      expect(ts.month).to eq(6)
      expect(ts.day).to eq(15)
      expect(ts.to_s).to eq("20220615000000")
    end
  end

  describe ".from_time" do
    it "creates a Timestamp from a Time object" do
      time = Time.utc(2023, 6, 15, 10, 30, 45)
      ts = described_class.from_time(time)
      expect(ts.to_s).to eq("20230615103045")
    end

    it "converts local time to UTC" do
      time = Time.new(2023, 6, 15, 10, 30, 45, "+05:00")
      ts = described_class.from_time(time)
      expect(ts.hour).to eq(5)
    end
  end

  describe ".now" do
    it "returns a Timestamp representing the current second" do
      now = Time.now.utc
      ts = described_class.now

      expect(ts.year).to eq(now.year)
      expect(ts.month).to eq(now.month)
      expect(ts.day).to eq(now.day)
      expect(ts.hour).to eq(now.hour)
      expect(ts.minute).to eq(now.min)
    end
  end

  describe ".coerce" do
    it "returns a Timestamp unchanged" do
      ts = described_class.new(year: 2022)
      expect(described_class.coerce(ts)).to equal(ts)
    end

    it "parses a String" do
      ts = described_class.coerce("20220113130051")
      expect(ts.year).to eq(2022)
    end

    it "converts a Time" do
      time = Time.utc(2023, 1, 1)
      ts = described_class.coerce(time)
      expect(ts.to_s).to eq("20230101000000")
    end

    it "raises ArgumentError for unsupported types" do
      expect do
        described_class.coerce(123)
      end.to raise_error(ArgumentError, /Cannot coerce/)
    end
  end

  describe "#to_s" do
    it "formats as 14-digit string" do
      ts = described_class.new(year: 2022, month: 1, day: 13, hour: 13,
                               minute: 0, second: 51)
      expect(ts.to_s).to eq("20220113130051")
      expect(ts.to_s.length).to eq(14)
    end
  end

  describe "#to_time" do
    it "returns the underlying UTC Time" do
      ts = described_class.new(year: 2022, month: 6, day: 15)
      expect(ts.to_time).to eq(Time.utc(2022, 6, 15))
    end
  end

  describe "comparison" do
    let(:earlier) { described_class.new(year: 2020) }
    let(:later) { described_class.new(year: 2022) }

    it "compares timestamps" do
      expect(earlier).to be < later
      expect(later).to be > earlier
    end

    it "supports equality" do
      expect(earlier).to eq(described_class.new(year: 2020))
    end

    it "returns nil for non-Timestamp comparison" do
      expect(earlier <=> "not a timestamp").to be_nil
    end
  end

  describe "#hash and #eql?" do
    it "produces stable hashes" do
      ts1 = described_class.new(year: 2022)
      ts2 = described_class.new(year: 2022)
      expect(ts1.hash).to eq(ts2.hash)
    end

    it "works as hash keys" do
      ts1 = described_class.new(year: 2022)
      ts2 = described_class.new(year: 2022)
      hash = { ts1 => "value" }
      expect(hash[ts2]).to eq("value")
    end
  end

  describe "attribute accessors" do
    subject(:ts) do
      described_class.new(year: 2022, month: 3, day: 15, hour: 14, minute: 30,
                          second: 45)
    end

    it { expect(ts.year).to eq(2022) }
    it { expect(ts.month).to eq(3) }
    it { expect(ts.day).to eq(15) }
    it { expect(ts.hour).to eq(14) }
    it { expect(ts.minute).to eq(30) }
    it { expect(ts.second).to eq(45) }
  end

  describe "#to_date" do
    it "returns a Date object" do
      ts = described_class.new(year: 2022, month: 6, day: 15)
      date = ts.to_date
      expect(date).to be_a(Date)
      expect(date.year).to eq(2022)
      expect(date.month).to eq(6)
      expect(date.day).to eq(15)
    end
  end

  describe "#to_i" do
    it "returns the unix epoch" do
      ts = described_class.new(year: 2022, month: 1, day: 1)
      expect(ts.to_i).to eq(Time.utc(2022, 1, 1).to_i)
    end
  end
end
