# frozen_string_literal: true

module LLMCapabilities
  class Detector
    # Capability vocabulary derived from RubyLLM's model capability strings.
    # See: https://github.com/crmne/ruby_llm
    KNOWN_CAPABILITIES = %i[
      streaming function_calling structured_output predicted_outputs
      distillation fine_tuning batch realtime image_generation
      speech_generation transcription translation citations
      reasoning caching moderation json_mode vision
    ].freeze

    def initialize(cache:, provider_capabilities: Configuration::DEFAULT_PROVIDER_CAPABILITIES, model_index: nil, ruby_llm_enabled: nil)
      @cache = cache
      @provider_capabilities = provider_capabilities
      @model_index = model_index
      @ruby_llm_enabled = ruby_llm_enabled
    end

    def supports?(model, capability, context: {})
      validate_capability!(capability)

      # Tier 1: Empirical cache (most authoritative, with full context)
      cached = @cache.lookup(model, capability, context: context)
      return cached unless cached.nil?

      # Tier 2: OpenRouter model index (base capability only)
      if @model_index
        index_result = @model_index.lookup(model, capability)
        return index_result unless index_result.nil?
      end

      # Tier 3: RubyLLM model registry (base capability only)
      ruby_llm_result = query_ruby_llm(model, capability)
      return ruby_llm_result unless ruby_llm_result.nil?

      # Tier 4: Provider-level heuristic (base capability only)
      provider_supports?(model, capability)
    end

    def provider_supports?(model, capability)
      provider = model.include?("/") ? model.split("/", 2).first : nil
      return false unless provider

      providers = @provider_capabilities[capability]
      return false unless providers

      providers.include?(provider)
    end

    private

    def validate_capability!(capability)
      return if KNOWN_CAPABILITIES.include?(capability)

      raise UnknownCapabilityError,
        "Unknown capability: #{capability.inspect}. Known capabilities: #{KNOWN_CAPABILITIES.join(", ")}"
    end

    def ruby_llm_available?
      if @ruby_llm_enabled.nil?
        @ruby_llm_enabled = defined?(RubyLLM) ? true : false
      end
      @ruby_llm_enabled
    end

    def query_ruby_llm(model, capability)
      return nil unless ruby_llm_available?

      model_info = RubyLLM.models.find(model)
      return nil unless model_info

      method_name = :"#{capability}?"
      if model_info.respond_to?(method_name)
        model_info.public_send(method_name)
      end
    rescue
      nil
    end
  end
end
