# frozen_string_literal: true

require "archaeo"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Lightweight test double for Archaeo::HttpClient
class FakeHttpClient
  attr_reader :last_url, :last_headers

  def initialize(responses = [])
    @responses = Array(responses)
    @index = 0
  end

  def get(url, headers: {})
    @last_url = url
    @last_headers = headers
    response = @responses[@index] || @responses.last
    @index += 1
    response
  end

  def self.response(status:, body: "", headers: {})
    Archaeo::HttpClient::Response.new(
      status: status,
      headers: headers,
      body: body,
    )
  end
end
