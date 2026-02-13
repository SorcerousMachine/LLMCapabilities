# frozen_string_literal: true

require "tmpdir"

RSpec.describe LLMCapabilities do
  let(:cache_dir) { Dir.mktmpdir }
  let(:cache_path) { File.join(cache_dir, "cache.json") }
  let(:index_path) { File.join(cache_dir, "index.json") }

  before do
    stub_request(:get, "https://openrouter.ai/api/v1/models")
      .to_return(status: 200, body: '{"data":[]}', headers: {"Content-Type" => "application/json"})

    described_class.configure do |config|
      config.cache_path = cache_path
      config.index_path = index_path
    end
  end

  after do
    described_class.reset!
    FileUtils.rm_rf(cache_dir)
  end

  describe ".configure" do
    it "sets cache_path" do
      expect(described_class.configuration.cache_path).to eq(cache_path)
    end

    it "accepts a block" do
      described_class.configure do |config|
        config.provider_capabilities = {structured_output: %w[openai]}
      end

      expect(described_class.configuration.provider_capabilities[:structured_output]).to eq(%w[openai])
    end
  end

  describe ".reset!" do
    it "resets configuration to defaults" do
      described_class.configure do |config|
        config.provider_capabilities = {structured_output: %w[openai]}
      end

      described_class.reset!

      expect(described_class.configuration.provider_capabilities[:structured_output]).to eq(%w[openai google anthropic deepseek])
      expect(described_class.configuration.cache_path).to eq(".llm_capabilities_cache.json")
      expect(described_class.configuration.index_path).to eq(".llm_capabilities_index.json")
    end
  end

  describe ".record and .lookup" do
    it "records and looks up a capability" do
      described_class.record("openai/o4-mini", :structured_output, context: {thinking: true}, supported: true)

      expect(described_class.lookup("openai/o4-mini", :structured_output, context: {thinking: true})).to be true
    end

    it "returns nil for unknown model" do
      expect(described_class.lookup("unknown/model", :structured_output)).to be_nil
    end
  end

  describe ".supports?" do
    it "returns true for cached supported model" do
      described_class.record("openai/o4-mini", :structured_output, supported: true)

      expect(described_class.supports?("openai/o4-mini", :structured_output)).to be true
    end

    it "falls through to provider heuristic when no cache" do
      expect(described_class.supports?("openai/o4-mini", :structured_output)).to be true
      expect(described_class.supports?("qwen/qwen3-235b", :structured_output)).to be false
    end

    it "raises UnknownCapabilityError for unknown capability" do
      expect { described_class.supports?("openai/o4-mini", :telepathy) }
        .to raise_error(LLMCapabilities::UnknownCapabilityError)
    end

    it "supports non-structured-output capabilities" do
      expect(described_class.supports?("openai/gpt-4o", :vision)).to be true
      expect(described_class.supports?("deepseek/deepseek-r1", :vision)).to be false
    end
  end

  describe ".clear!" do
    it "clears all cached entries" do
      described_class.record("openai/o4-mini", :structured_output, supported: true)
      described_class.clear!

      expect(described_class.size).to eq(0)
    end
  end

  describe ".size" do
    it "returns the number of cached entries" do
      expect(described_class.size).to eq(0)

      described_class.record("a/b", :structured_output, supported: true)
      described_class.record("c/d", :vision, context: {thinking: true}, supported: false)

      expect(described_class.size).to eq(2)
    end
  end
end
