# frozen_string_literal: true
# typed: true

require "json"
require "fileutils"

module LLMCapabilities
  class Cache
    def initialize(path: Configuration::DEFAULT_CACHE_PATH, max_age: Configuration::DEFAULT_MAX_AGE)
      @path = path
      @max_age = max_age
      @entries = nil
    end

    def lookup(model, capability, context: {})
      load_cache!
      entry = @entries[cache_key(model, capability, context)]
      return nil unless entry.is_a?(Hash)

      if @max_age && entry["recorded_at"]
        elapsed = Time.now.to_i - entry["recorded_at"]
        return nil if elapsed > @max_age
      end

      entry["supported"]
    end

    def record(model, capability, supported:, context: {})
      load_cache!
      @entries[cache_key(model, capability, context)] = {
        "supported" => supported,
        "recorded_at" => Time.now.to_i
      }
      persist!
    end

    def clear!
      @entries = {}
      persist!
    end

    def size
      load_cache!
      @entries.length
    end

    private

    def cache_key(model, capability, context)
      base = "#{model}:#{capability}"
      return base if context.empty?

      pairs = context.sort_by { |k, _| k.to_s }.map { |k, v| "#{k}=#{v}" }.join(",")
      "#{base}:#{pairs}"
    end

    def load_cache!
      return unless @entries.nil?

      @entries = if File.exist?(@path)
        File.open(@path, File::RDONLY) do |f|
          f.flock(File::LOCK_SH)
          JSON.parse(f.read)
        end
      else
        {}
      end
    rescue JSON::ParserError
      @entries = {}
    end

    def persist!
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

      File.open(@path, File::CREAT | File::WRONLY | File::TRUNC) do |f|
        f.flock(File::LOCK_EX)
        f.write(JSON.pretty_generate(@entries))
      end
    end
  end
end
