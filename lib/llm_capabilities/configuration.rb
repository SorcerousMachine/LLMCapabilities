# frozen_string_literal: true

module LLMCapabilities
  class Configuration
    DEFAULT_CACHE_PATH = ".llm_capabilities_cache.json"
    DEFAULT_INDEX_PATH = ".llm_capabilities_index.json"
    DEFAULT_INDEX_TTL = 86_400 # 24 hours in seconds
    DEFAULT_MAX_AGE = 2_592_000 # 30 days in seconds

    DEFAULT_PROVIDER_CAPABILITIES = {
      structured_output: %w[openai google anthropic deepseek],
      function_calling: %w[openai google anthropic deepseek],
      vision: %w[openai google anthropic],
      streaming: %w[openai google anthropic deepseek]
    }.freeze

    attr_accessor :cache_path, :index_path, :index_ttl, :provider_capabilities, :max_age

    def initialize
      @cache_path = DEFAULT_CACHE_PATH
      @index_path = DEFAULT_INDEX_PATH
      @index_ttl = DEFAULT_INDEX_TTL
      @provider_capabilities = DEFAULT_PROVIDER_CAPABILITIES.transform_values(&:dup)
      @max_age = DEFAULT_MAX_AGE
    end
  end
end
