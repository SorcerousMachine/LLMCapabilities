# frozen_string_literal: true

require "tmpdir"

RSpec.describe LLMCapabilities::Detector do
  let(:cache_dir) { Dir.mktmpdir }
  let(:cache) { LLMCapabilities::Cache.new(path: File.join(cache_dir, "cache.json")) }
  subject(:detector) do
    described_class.new(cache: cache, ruby_llm_enabled: false)
  end

  after do
    FileUtils.rm_rf(cache_dir)
  end

  describe "#provider_supports?" do
    it "returns true for openai with structured_output" do
      expect(detector.provider_supports?("openai/o4-mini", :structured_output)).to be true
    end

    it "returns true for google with structured_output" do
      expect(detector.provider_supports?("google/gemini-2.5-flash", :structured_output)).to be true
    end

    it "returns true for anthropic with structured_output" do
      expect(detector.provider_supports?("anthropic/claude-sonnet-4.5", :structured_output)).to be true
    end

    it "returns true for deepseek with structured_output" do
      expect(detector.provider_supports?("deepseek/deepseek-r1-0528", :structured_output)).to be true
    end

    it "returns false for qwen with structured_output" do
      expect(detector.provider_supports?("qwen/qwen3-235b-a22b", :structured_output)).to be false
    end

    it "returns false for meta-llama" do
      expect(detector.provider_supports?("meta-llama/llama-3-70b", :structured_output)).to be false
    end

    it "returns false for bare model names without provider" do
      expect(detector.provider_supports?("gpt-4o", :structured_output)).to be false
    end

    it "returns true for openai with vision" do
      expect(detector.provider_supports?("openai/gpt-4o", :vision)).to be true
    end

    it "returns false for deepseek with vision" do
      expect(detector.provider_supports?("deepseek/deepseek-r1", :vision)).to be false
    end

    it "returns false for capabilities not in provider_capabilities" do
      expect(detector.provider_supports?("openai/o4-mini", :image_generation)).to be false
    end

    it "uses configured provider_capabilities" do
      custom_detector = described_class.new(
        cache: cache,
        provider_capabilities: {structured_output: %w[openai]},
        ruby_llm_enabled: false
      )

      expect(custom_detector.provider_supports?("openai/o4-mini", :structured_output)).to be true
      expect(custom_detector.provider_supports?("anthropic/claude-sonnet-4.5", :structured_output)).to be false
    end
  end

  describe "#supports?" do
    context "unknown capability validation" do
      it "raises UnknownCapabilityError for unknown capability" do
        expect { detector.supports?("openai/o4-mini", :telepathy) }
          .to raise_error(LLMCapabilities::UnknownCapabilityError, /Unknown capability.*:telepathy/)
      end
    end

    context "tier 1: empirical cache" do
      it "returns cached true when cache says supported" do
        cache.record("openai/o4-mini", :structured_output, context: {thinking: true}, supported: true)

        expect(detector.supports?("openai/o4-mini", :structured_output, context: {thinking: true})).to be true
      end

      it "returns cached false when cache says unsupported" do
        cache.record("anthropic/claude-haiku-4.5", :structured_output, context: {thinking: true}, supported: false)

        expect(detector.supports?("anthropic/claude-haiku-4.5", :structured_output, context: {thinking: true})).to be false
      end

      it "overrides provider heuristic with cached negative" do
        cache.record("anthropic/claude-haiku-4.5", :structured_output, context: {thinking: true}, supported: false)

        expect(detector.supports?("anthropic/claude-haiku-4.5", :structured_output, context: {thinking: true})).to be false
      end
    end

    context "tier 2: OpenRouter model index" do
      let(:model_index) { instance_double(LLMCapabilities::ModelIndex) }

      let(:detector_with_index) do
        described_class.new(cache: cache, model_index: model_index, ruby_llm_enabled: false)
      end

      it "uses model index when cache misses" do
        allow(model_index).to receive(:lookup).with("openai/o4-mini", :structured_output).and_return(true)

        expect(detector_with_index.supports?("openai/o4-mini", :structured_output)).to be true
      end

      it "returns false from model index" do
        allow(model_index).to receive(:lookup).with("qwen/qwen3-235b", :structured_output).and_return(nil)

        expect(detector_with_index.supports?("qwen/qwen3-235b", :structured_output)).to be false
      end

      it "falls through when model index returns nil" do
        allow(model_index).to receive(:lookup).with("openai/o4-mini", :streaming).and_return(nil)

        # Falls through to tier 4 (provider heuristic), which has :streaming for openai
        expect(detector_with_index.supports?("openai/o4-mini", :streaming)).to be true
      end

      it "ignores context for model index lookup" do
        allow(model_index).to receive(:lookup).with("openai/o4-mini", :structured_output).and_return(true)

        expect(detector_with_index.supports?("openai/o4-mini", :structured_output, context: {thinking: true})).to be true
      end
    end

    context "tier 3: RubyLLM model registry" do
      let(:detector_with_ruby_llm) do
        described_class.new(cache: cache, ruby_llm_enabled: true)
      end

      before do
        stub_const("RubyLLM", Module.new {
          def self.models
          end
        })
      end

      it "uses RubyLLM structured_output? when available" do
        model_info = double("ModelInfo", structured_output?: true)
        models = double("Models")
        allow(models).to receive(:find).with("openai/o4-mini").and_return(model_info)
        allow(RubyLLM).to receive(:models).and_return(models)

        expect(detector_with_ruby_llm.supports?("openai/o4-mini", :structured_output)).to be true
      end

      it "returns false when RubyLLM says no structured_output" do
        model_info = double("ModelInfo", structured_output?: false)
        models = double("Models")
        allow(models).to receive(:find).with("qwen/qwen3-235b").and_return(model_info)
        allow(RubyLLM).to receive(:models).and_return(models)

        expect(detector_with_ruby_llm.supports?("qwen/qwen3-235b", :structured_output)).to be false
      end

      it "queries vision? for vision capability" do
        model_info = double("ModelInfo", vision?: true)
        models = double("Models")
        allow(models).to receive(:find).with("openai/gpt-4o").and_return(model_info)
        allow(RubyLLM).to receive(:models).and_return(models)

        expect(detector_with_ruby_llm.supports?("openai/gpt-4o", :vision)).to be true
      end

      it "falls through to tier 4 when RubyLLM raises" do
        allow(RubyLLM).to receive(:models).and_raise(RuntimeError, "not loaded")

        expect(detector_with_ruby_llm.supports?("openai/o4-mini", :structured_output)).to be true
      end

      it "falls through to tier 4 when model not found" do
        models = double("Models")
        allow(models).to receive(:find).with("custom/model").and_return(nil)
        allow(RubyLLM).to receive(:models).and_return(models)

        expect(detector_with_ruby_llm.supports?("custom/model", :structured_output)).to be false
      end
    end

    context "tier 4: provider heuristic fallback" do
      it "falls back to provider heuristic for supported providers" do
        expect(detector.supports?("openai/o4-mini", :structured_output)).to be true
      end

      it "falls back to provider heuristic for unsupported providers" do
        expect(detector.supports?("qwen/qwen3-235b", :structured_output)).to be false
      end

      it "checks non-structured-output capability" do
        expect(detector.supports?("openai/gpt-4o", :vision)).to be true
        expect(detector.supports?("deepseek/deepseek-r1", :vision)).to be false
      end
    end

    context "tier priority" do
      let(:model_index) { instance_double(LLMCapabilities::ModelIndex) }

      let(:detector_full) do
        described_class.new(
          cache: cache,
          model_index: model_index,
          ruby_llm_enabled: false
        )
      end

      it "cache overrides model index" do
        allow(model_index).to receive(:lookup).with("openai/o4-mini", :structured_output).and_return(true)
        cache.record("openai/o4-mini", :structured_output, supported: false)

        expect(detector_full.supports?("openai/o4-mini", :structured_output)).to be false
      end

      it "cache overrides RubyLLM" do
        stub_const("RubyLLM", Module.new {
          def self.models
          end
        })
        detector_with_llm = described_class.new(cache: cache, ruby_llm_enabled: true)

        model_info = double("ModelInfo", structured_output?: true)
        models = double("Models")
        allow(models).to receive(:find).with("openai/o4-mini").and_return(model_info)
        allow(RubyLLM).to receive(:models).and_return(models)

        cache.record("openai/o4-mini", :structured_output, supported: false)

        expect(detector_with_llm.supports?("openai/o4-mini", :structured_output)).to be false
      end

      it "model index overrides provider heuristic" do
        allow(model_index).to receive(:lookup).with("qwen/qwen3-235b", :structured_output).and_return(true)

        expect(detector_full.supports?("qwen/qwen3-235b", :structured_output)).to be true
      end
    end
  end

  describe "lazy RubyLLM detection" do
    it "skips RubyLLM when explicitly disabled" do
      disabled_detector = described_class.new(cache: cache, ruby_llm_enabled: false)

      # Should fall through to tier 4 without calling RubyLLM
      expect(disabled_detector.supports?("openai/o4-mini", :structured_output)).to be true
    end

    it "auto-detects RubyLLM availability when ruby_llm_enabled is nil" do
      auto_detector = described_class.new(cache: cache, ruby_llm_enabled: nil)

      # RubyLLM is not defined in test env, so auto-detection sets @ruby_llm_enabled = false
      # Falls through to tier 4
      expect(auto_detector.supports?("openai/o4-mini", :structured_output)).to be true
    end
  end

  describe "model string parsing edge cases" do
    it "extracts provider from model with multiple slashes" do
      expect(detector.provider_supports?("company/division/model", :structured_output)).to be false
    end

    it "extracts provider from model with trailing slash" do
      expect(detector.provider_supports?("openai/", :structured_output)).to be true
    end

    it "returns false for model with leading slash (empty provider)" do
      expect(detector.provider_supports?("/model", :structured_output)).to be false
    end
  end

  describe "validate_capability! edge cases" do
    it "accepts every KNOWN_CAPABILITY without raising" do
      LLMCapabilities::Detector::KNOWN_CAPABILITIES.each do |cap|
        expect { detector.supports?("openai/o4-mini", cap) }.not_to raise_error
      end
    end

    it "raises for string capability instead of symbol" do
      expect { detector.supports?("openai/o4-mini", "structured_output") }
        .to raise_error(LLMCapabilities::UnknownCapabilityError)
    end
  end

  describe "query_ruby_llm edge cases" do
    let(:detector_with_ruby_llm) do
      described_class.new(cache: cache, ruby_llm_enabled: true)
    end

    before do
      stub_const("RubyLLM", Module.new {
        def self.models
        end
      })
    end

    it "returns nil when model_info does not respond_to capability method" do
      model_info = double("ModelInfo")
      models = double("Models")
      allow(models).to receive(:find).with("openai/o4-mini").and_return(model_info)
      allow(RubyLLM).to receive(:models).and_return(models)

      # model_info doesn't have structured_output? — falls through to tier 4
      expect(detector_with_ruby_llm.supports?("openai/o4-mini", :structured_output)).to be true
    end

    it "catches TypeError from capability method and returns nil" do
      model_info = double("ModelInfo")
      allow(model_info).to receive(:respond_to?).with(:structured_output?).and_return(true)
      allow(model_info).to receive(:structured_output?).and_raise(TypeError, "something went wrong")
      models = double("Models")
      allow(models).to receive(:find).with("openai/o4-mini").and_return(model_info)
      allow(RubyLLM).to receive(:models).and_return(models)

      # Falls through to tier 4 due to rescue
      expect(detector_with_ruby_llm.supports?("openai/o4-mini", :structured_output)).to be true
    end

    it "catches error when RubyLLM.models returns nil" do
      allow(RubyLLM).to receive(:models).and_return(nil)

      # nil.find raises NoMethodError, rescued, falls through to tier 4
      expect(detector_with_ruby_llm.supports?("openai/o4-mini", :structured_output)).to be true
    end
  end

  describe "provider_supports? with empty provider_capabilities" do
    let(:empty_detector) do
      described_class.new(cache: cache, provider_capabilities: {}, ruby_llm_enabled: false)
    end

    it "returns false for all capabilities" do
      expect(empty_detector.provider_supports?("openai/o4-mini", :structured_output)).to be false
      expect(empty_detector.provider_supports?("openai/o4-mini", :vision)).to be false
      expect(empty_detector.provider_supports?("openai/o4-mini", :streaming)).to be false
    end
  end

  describe "all 4 configured default capabilities" do
    it "includes structured_output, function_calling, vision, and streaming" do
      defaults = LLMCapabilities::Configuration::DEFAULT_PROVIDER_CAPABILITIES
      expect(defaults.keys).to contain_exactly(:structured_output, :function_calling, :vision, :streaming)
    end
  end
end
