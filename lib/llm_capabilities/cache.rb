# typed: strict
# frozen_string_literal: true

require "json"
require "fileutils"

module LLMCapabilities
  class Cache
    extend T::Sig

    sig { params(path: String, max_age: T.nilable(Integer)).void }
    def initialize(path: Configuration::DEFAULT_CACHE_PATH, max_age: Configuration::DEFAULT_MAX_AGE)
      @path = T.let(path, String)
      @max_age = T.let(max_age, T.nilable(Integer))
      @entries = T.let(nil, T.nilable(T::Hash[String, T::Hash[String, T.untyped]]))
    end

    sig { params(model: String, thinking: T::Boolean).returns(T.nilable(T::Boolean)) }
    def lookup(model, thinking: false)
      load_cache!
      entry = T.must(@entries)[cache_key(model, thinking)]
      return nil unless entry

      if @max_age && entry["recorded_at"]
        elapsed = Time.now.to_i - T.cast(entry["recorded_at"], Integer)
        return nil if elapsed > @max_age
      end

      T.cast(entry["supported"], T::Boolean)
    end

    sig { params(model: String, thinking: T::Boolean, supported: T::Boolean).void }
    def record(model, thinking: false, supported: false)
      load_cache!
      T.must(@entries)[cache_key(model, thinking)] = {
        "supported" => supported,
        "recorded_at" => Time.now.to_i
      }
      persist!
    end

    sig { void }
    def clear!
      @entries = {}
      persist!
    end

    sig { returns(Integer) }
    def size
      load_cache!
      T.must(@entries).length
    end

    private

    sig { params(model: String, thinking: T::Boolean).returns(String) }
    def cache_key(model, thinking)
      "#{model}:thinking=#{thinking}"
    end

    sig { void }
    def load_cache!
      return unless @entries.nil?

      @entries = if File.exist?(@path)
        File.open(@path, File::RDONLY) do |f|
          f.flock(File::LOCK_SH)
          data = JSON.parse(f.read)
          migrate(data)
        end
      else
        {}
      end
    rescue JSON::ParserError
      @entries = {}
    end

    sig { void }
    def persist!
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

      File.open(@path, File::CREAT | File::WRONLY | File::TRUNC) do |f|
        f.flock(File::LOCK_EX)
        f.write(JSON.pretty_generate(@entries))
      end
    end

    sig { params(data: T.untyped).returns(T::Hash[String, T::Hash[String, T.untyped]]) }
    def migrate(data)
      result = T.let({}, T::Hash[String, T::Hash[String, T.untyped]])
      T.cast(data, T::Hash[String, T.untyped]).each do |key, value|
        result[key] = case value
        when Hash
          value
        else
          # Legacy format: bare boolean → wrap with current timestamp
          {"supported" => value, "recorded_at" => Time.now.to_i}
        end
      end
      result
    end
  end
end
