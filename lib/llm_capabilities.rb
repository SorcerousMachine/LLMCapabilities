# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "llm_capabilities/version"
require_relative "llm_capabilities/configuration"
require_relative "llm_capabilities/cache"
require_relative "llm_capabilities/detector"

module LLMCapabilities
  extend T::Sig

  @configuration = T.let(nil, T.nilable(Configuration))
  @cache = T.let(nil, T.nilable(Cache))
  @detector = T.let(nil, T.nilable(Detector))

  class << self
    extend T::Sig

    sig { returns(Configuration) }
    def configuration
      @configuration ||= Configuration.new
    end

    sig { params(block: T.proc.params(config: Configuration).void).void }
    def configure(&block)
      block.call(configuration)
      @cache = nil
      @detector = nil
    end

    sig { params(model: String, thinking: T::Boolean).returns(T::Boolean) }
    def supports_schema?(model, thinking: false)
      detector.supports_schema?(model, thinking: thinking)
    end

    sig { params(model: String, thinking: T::Boolean, supported: T::Boolean).void }
    def record(model, thinking:, supported:)
      cache.record(model, thinking: thinking, supported: supported)
    end

    sig { params(model: String, thinking: T::Boolean).returns(T.nilable(T::Boolean)) }
    def lookup(model, thinking: false)
      cache.lookup(model, thinking: thinking)
    end

    sig { void }
    def clear!
      cache.clear!
    end

    sig { returns(Integer) }
    def size
      cache.size
    end

    sig { void }
    def reset!
      @configuration = nil
      @cache = nil
      @detector = nil
    end

    private

    sig { returns(Cache) }
    def cache
      @cache ||= Cache.new(
        path: configuration.cache_path,
        max_age: configuration.max_age
      )
    end

    sig { returns(Detector) }
    def detector
      @detector ||= Detector.new(
        cache: cache,
        providers: configuration.providers
      )
    end
  end
end
