# frozen_string_literal: true

RSpec.describe LLMCapabilities::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "has default cache_path" do
      expect(config.cache_path).to eq(".llm_capabilities_cache.json")
    end

    it "has default index_path" do
      expect(config.index_path).to eq(".llm_capabilities_index.json")
    end

    it "has default index_ttl of 24 hours" do
      expect(config.index_ttl).to eq(86_400)
    end

    it "has default provider_capabilities with 4 capabilities" do
      expect(config.provider_capabilities.keys).to contain_exactly(
        :structured_output, :function_calling, :vision, :streaming
      )
    end

    it "has default structured_output providers" do
      expect(config.provider_capabilities[:structured_output]).to eq(%w[openai google anthropic deepseek])
    end

    it "has default vision providers" do
      expect(config.provider_capabilities[:vision]).to eq(%w[openai google anthropic])
    end

    it "has default max_age of 30 days" do
      expect(config.max_age).to eq(2_592_000)
    end
  end

  describe "custom values" do
    it "allows setting cache_path" do
      config.cache_path = "/tmp/custom_cache.json"
      expect(config.cache_path).to eq("/tmp/custom_cache.json")
    end

    it "allows setting index_path" do
      config.index_path = "/tmp/custom_index.json"
      expect(config.index_path).to eq("/tmp/custom_index.json")
    end

    it "allows setting index_ttl" do
      config.index_ttl = 3600
      expect(config.index_ttl).to eq(3600)
    end

    it "allows setting provider_capabilities" do
      config.provider_capabilities = {structured_output: %w[openai]}
      expect(config.provider_capabilities).to eq({structured_output: %w[openai]})
    end

    it "allows setting max_age" do
      config.max_age = 86_400
      expect(config.max_age).to eq(86_400)
    end

    it "allows disabling expiration with nil max_age" do
      config.max_age = nil
      expect(config.max_age).to be_nil
    end
  end

  describe "isolation" do
    it "does not share provider_capabilities between instances" do
      config_a = described_class.new
      config_b = described_class.new

      config_a.provider_capabilities[:structured_output] << "custom"

      expect(config_b.provider_capabilities[:structured_output]).not_to include("custom")
    end
  end
end
