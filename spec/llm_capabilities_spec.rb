# frozen_string_literal: true

require "tmpdir"

RSpec.describe LLMCapabilities do
  let(:cache_dir) { Dir.mktmpdir }
  let(:cache_path) { File.join(cache_dir, "cache.json") }

  before do
    described_class.configure do |config|
      config.cache_path = cache_path
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
        config.providers = %w[openai]
      end

      expect(described_class.configuration.providers).to eq(%w[openai])
    end
  end

  describe ".reset!" do
    it "resets configuration to defaults" do
      described_class.configure do |config|
        config.providers = %w[openai]
      end

      described_class.reset!

      expect(described_class.configuration.providers).to eq(%w[openai google anthropic deepseek])
      expect(described_class.configuration.cache_path).to eq(".llm_capabilities_cache.json")
    end
  end

  describe ".record and .lookup" do
    it "records and looks up a capability" do
      described_class.record("openai/o4-mini", thinking: true, supported: true)

      expect(described_class.lookup("openai/o4-mini", thinking: true)).to be true
    end

    it "returns nil for unknown model" do
      expect(described_class.lookup("unknown/model")).to be_nil
    end
  end

  describe ".supports_schema?" do
    it "returns true for cached supported model" do
      described_class.record("openai/o4-mini", thinking: false, supported: true)

      expect(described_class.supports_schema?("openai/o4-mini")).to be true
    end

    it "falls through to provider heuristic when no cache" do
      expect(described_class.supports_schema?("openai/o4-mini")).to be true
      expect(described_class.supports_schema?("qwen/qwen3-235b")).to be false
    end
  end

  describe ".clear!" do
    it "clears all cached entries" do
      described_class.record("openai/o4-mini", thinking: false, supported: true)
      described_class.clear!

      expect(described_class.size).to eq(0)
    end
  end

  describe ".size" do
    it "returns the number of cached entries" do
      expect(described_class.size).to eq(0)

      described_class.record("a/b", thinking: false, supported: true)
      described_class.record("c/d", thinking: true, supported: false)

      expect(described_class.size).to eq(2)
    end
  end
end
