# typed: strict
# frozen_string_literal: true

module LLMCapabilities
  class Configuration
    extend T::Sig

    DEFAULT_CACHE_PATH = T.let(
      ".llm_capabilities_cache.json",
      String
    )

    DEFAULT_PROVIDERS = T.let(
      %w[openai google anthropic deepseek].freeze,
      T::Array[String]
    )

    DEFAULT_MAX_AGE = T.let(2_592_000, Integer) # 30 days in seconds

    sig { returns(String) }
    attr_accessor :cache_path

    sig { returns(T::Array[String]) }
    attr_accessor :providers

    sig { returns(T.nilable(Integer)) }
    attr_accessor :max_age

    sig { void }
    def initialize
      @cache_path = T.let(DEFAULT_CACHE_PATH, String)
      @providers = T.let(DEFAULT_PROVIDERS.dup, T::Array[String])
      @max_age = T.let(DEFAULT_MAX_AGE, T.nilable(Integer))
    end
  end
end
