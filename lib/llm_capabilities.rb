# frozen_string_literal: true

require_relative "llm_capabilities/version"
require_relative "llm_capabilities/configuration"
require_relative "llm_capabilities/cache"
require_relative "llm_capabilities/model_index"
require_relative "llm_capabilities/detector"

module LLMCapabilities
  class Error < StandardError; end
  class UnknownCapabilityError < Error; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure(&block)
      block.call(configuration)
      @cache = nil
      @model_index = nil
      @detector = nil
    end

    def supports?(model, capability, context: {})
      detector.supports?(model, capability, context: context)
    end

    def record(model, capability, supported:, context: {})
      cache.record(model, capability, supported: supported, context: context)
    end

    def lookup(model, capability, context: {})
      cache.lookup(model, capability, context: context)
    end

    def clear!
      cache.clear!
    end

    def size
      cache.size
    end

    def reset!
      @configuration = nil
      @cache = nil
      @model_index = nil
      @detector = nil
    end

    private

    def cache
      @cache ||= Cache.new(
        path: configuration.cache_path,
        max_age: configuration.max_age
      )
    end

    def model_index
      @model_index ||= ModelIndex.new(
        path: configuration.index_path,
        ttl: configuration.index_ttl
      )
    end

    def detector
      @detector ||= Detector.new(
        cache: cache,
        provider_capabilities: configuration.provider_capabilities,
        model_index: model_index
      )
    end
  end
end
