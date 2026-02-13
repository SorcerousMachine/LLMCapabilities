# frozen_string_literal: true

require "tmpdir"
require "ruby_llm"

RSpec.describe LLMCapabilities::Detector do
  let(:cache_dir) { Dir.mktmpdir }
  let(:cache) { LLMCapabilities::Cache.new(path: File.join(cache_dir, "cache.json")) }
  subject(:detector) { described_class.new(cache: cache, ruby_llm_enabled: false) }

  after do
    FileUtils.rm_rf(cache_dir)
  end

  describe "#provider_supports_schema?" do
    it "returns true for openai provider" do
      expect(detector.provider_supports_schema?("openai/o4-mini")).to be true
    end

    it "returns true for google provider" do
      expect(detector.provider_supports_schema?("google/gemini-2.5-flash")).to be true
    end

    it "returns true for anthropic provider" do
      expect(detector.provider_supports_schema?("anthropic/claude-sonnet-4.5")).to be true
    end

    it "returns true for deepseek provider" do
      expect(detector.provider_supports_schema?("deepseek/deepseek-r1-0528")).to be true
    end

    it "returns false for qwen provider" do
      expect(detector.provider_supports_schema?("qwen/qwen3-235b-a22b")).to be false
    end

    it "returns false for meta-llama provider" do
      expect(detector.provider_supports_schema?("meta-llama/llama-3-70b")).to be false
    end

    it "returns false for bare model names without provider" do
      expect(detector.provider_supports_schema?("gpt-4o")).to be false
    end

    it "uses configured providers list" do
      custom_detector = described_class.new(
        cache: cache,
        providers: %w[openai],
        ruby_llm_enabled: false
      )

      expect(custom_detector.provider_supports_schema?("openai/o4-mini")).to be true
      expect(custom_detector.provider_supports_schema?("anthropic/claude-sonnet-4.5")).to be false
    end
  end

  describe "#supports_schema?" do
    context "tier 1: empirical cache" do
      it "returns cached true when cache says supported" do
        cache.record("openai/o4-mini", thinking: true, supported: true)

        expect(detector.supports_schema?("openai/o4-mini", thinking: true)).to be true
      end

      it "returns cached false when cache says unsupported" do
        cache.record("anthropic/claude-haiku-4.5", thinking: true, supported: false)

        expect(detector.supports_schema?("anthropic/claude-haiku-4.5", thinking: true)).to be false
      end

      it "overrides provider heuristic with cached negative" do
        cache.record("anthropic/claude-haiku-4.5", thinking: true, supported: false)

        expect(detector.supports_schema?("anthropic/claude-haiku-4.5", thinking: true)).to be false
      end
    end

    context "tier 2: RubyLLM model registry" do
      let(:detector_with_ruby_llm) do
        described_class.new(cache: cache, ruby_llm_enabled: true)
      end

      it "uses RubyLLM structured_output? when available" do
        model_info = double("ModelInfo", structured_output?: true)
        models = double("Models")
        allow(models).to receive(:find).with("openai/o4-mini").and_return(model_info)
        allow(RubyLLM).to receive(:models).and_return(models)

        expect(detector_with_ruby_llm.supports_schema?("openai/o4-mini")).to be true
      end

      it "returns false when RubyLLM says no structured_output" do
        model_info = double("ModelInfo", structured_output?: false)
        models = double("Models")
        allow(models).to receive(:find).with("qwen/qwen3-235b").and_return(model_info)
        allow(RubyLLM).to receive(:models).and_return(models)

        expect(detector_with_ruby_llm.supports_schema?("qwen/qwen3-235b")).to be false
      end

      it "falls through to tier 3 when RubyLLM raises" do
        allow(RubyLLM).to receive(:models).and_raise(RuntimeError, "not loaded")

        expect(detector_with_ruby_llm.supports_schema?("openai/o4-mini")).to be true
      end

      it "falls through to tier 3 when model not found" do
        models = double("Models")
        allow(models).to receive(:find).with("custom/model").and_return(nil)
        allow(RubyLLM).to receive(:models).and_return(models)

        expect(detector_with_ruby_llm.supports_schema?("custom/model")).to be false
      end
    end

    context "tier 3: provider heuristic fallback" do
      it "falls back to provider heuristic for supported providers" do
        expect(detector.supports_schema?("openai/o4-mini")).to be true
      end

      it "falls back to provider heuristic for unsupported providers" do
        expect(detector.supports_schema?("qwen/qwen3-235b")).to be false
      end
    end

    context "tier priority" do
      let(:detector_with_ruby_llm) do
        described_class.new(cache: cache, ruby_llm_enabled: true)
      end

      it "cache overrides RubyLLM" do
        model_info = double("ModelInfo", structured_output?: true)
        models = double("Models")
        allow(models).to receive(:find).with("openai/o4-mini").and_return(model_info)
        allow(RubyLLM).to receive(:models).and_return(models)

        cache.record("openai/o4-mini", thinking: false, supported: false)

        expect(detector_with_ruby_llm.supports_schema?("openai/o4-mini", thinking: false)).to be false
      end
    end
  end

  describe "lazy RubyLLM detection" do
    it "auto-detects RubyLLM when ruby_llm_enabled is nil" do
      # RubyLLM is defined in test environment (it's a dev dep)
      auto_detector = described_class.new(cache: cache)

      model_info = double("ModelInfo", structured_output?: true)
      models = double("Models")
      allow(models).to receive(:find).with("openai/o4-mini").and_return(model_info)
      allow(RubyLLM).to receive(:models).and_return(models)

      expect(auto_detector.supports_schema?("openai/o4-mini")).to be true
    end

    it "skips RubyLLM when explicitly disabled" do
      disabled_detector = described_class.new(cache: cache, ruby_llm_enabled: false)

      # Even though RubyLLM is defined, it should not be called
      expect(RubyLLM).not_to receive(:models)

      disabled_detector.supports_schema?("openai/o4-mini")
    end
  end
end
