# frozen_string_literal: true

require "yaml"

module Archaeo
  # Manages persistent configuration across sessions.
  #
  # Loads settings from .archaeo.yml files, supports named profiles,
  # and falls back to sensible defaults. Settings cascade: defaults
  # < global config < profile overrides.
  class Configuration
    DEFAULTS = {
      "output_dir" => "archive",
      "format" => "table",
      "rate_limit" => 0,
      "concurrency" => 1,
      "max_retries" => 3,
    }.freeze

    def initialize(path: ".archaeo.yml")
      @path = path
      @data = load_config
    end

    def get(key, profile: nil)
      keys = key.to_s.split(".")
      value = dig_nested(@data, keys, profile)
      value.nil? ? DEFAULTS[keys.last] : value
    end

    def profile(name)
      profiles = @data["profiles"] || {}
      profiles[name.to_s] || {}
    end

    def profiles
      (@data["profiles"] || {}).keys
    end

    def set(key, value, profile: nil)
      if profile
        @data["profiles"] ||= {}
        @data["profiles"][profile.to_s] ||= {}
        @data["profiles"][profile.to_s][key.to_s] = value
      else
        @data["defaults"] ||= {}
        @data["defaults"][key.to_s] = value
      end
      save_config
    end

    def to_h
      {
        defaults: @data.fetch("defaults", {}),
        profiles: @data.fetch("profiles", {}),
      }
    end

    def save(path: nil)
      target = path || @path
      File.write(target, YAML.dump(@data))
    end

    private

    def load_config
      return {} unless File.exist?(@path)

      content = File.read(@path)
      YAML.safe_load(content, permitted_classes: [Symbol]) || {}
    rescue StandardError
      {}
    end

    def save_config
      FileUtils.mkdir_p(File.dirname(@path)) unless File.dirname(@path) == "."
      File.write(@path, YAML.dump(@data))
    end

    def dig_nested(data, keys, profile_name)
      if profile_name
        profile_data = data.dig("profiles", profile_name.to_s) || {}
        return dig_value(profile_data, keys)
      end

      defaults = data["defaults"] || {}
      dig_value(defaults, keys)
    end

    def dig_value(hash, keys)
      keys.reduce(hash) { |h, k| h.is_a?(Hash) ? h[k] : nil }
    end
  end
end
