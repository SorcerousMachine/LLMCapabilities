# typed: strict
# frozen_string_literal: true

module LLMCapabilities
  class Detector
    extend T::Sig

    sig do
      params(
        cache: Cache,
        providers: T::Array[String],
        ruby_llm_enabled: T.nilable(T::Boolean)
      ).void
    end
    def initialize(cache:, providers: Configuration::DEFAULT_PROVIDERS.dup, ruby_llm_enabled: nil)
      @cache = T.let(cache, Cache)
      @providers = T.let(providers, T::Array[String])
      @ruby_llm_enabled = T.let(ruby_llm_enabled, T.nilable(T::Boolean))
    end

    sig { params(model: String, thinking: T::Boolean).returns(T::Boolean) }
    def supports_schema?(model, thinking: false)
      # Tier 1: Empirical cache (most authoritative)
      cached = @cache.lookup(model, thinking: thinking)
      return cached unless cached.nil?

      # Tier 2: RubyLLM model registry
      ruby_llm_result = query_ruby_llm(model)
      return ruby_llm_result unless ruby_llm_result.nil?

      # Tier 3: Provider-level heuristic
      provider_supports_schema?(model)
    end

    sig { params(model: String).returns(T::Boolean) }
    def provider_supports_schema?(model)
      provider = model.include?("/") ? T.must(model.split("/", 2).first) : nil
      return false unless provider

      @providers.include?(provider)
    end

    private

    sig { returns(T::Boolean) }
    def ruby_llm_available?
      if @ruby_llm_enabled.nil?
        @ruby_llm_enabled = defined?(RubyLLM) ? true : false
      end
      @ruby_llm_enabled
    end

    sig { params(model: String).returns(T.nilable(T::Boolean)) }
    def query_ruby_llm(model)
      return nil unless ruby_llm_available?

      model_info = T.unsafe(RubyLLM).models.find(model)
      return nil unless model_info

      if model_info.respond_to?(:structured_output?)
        model_info.structured_output?
      end
    rescue
      nil
    end
  end
end
