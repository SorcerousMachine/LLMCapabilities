# frozen_string_literal: true

RSpec.describe LLMCapabilities::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "has default cache_path" do
      expect(config.cache_path).to eq(".llm_capabilities_cache.json")
    end

    it "has default providers" do
      expect(config.providers).to eq(%w[openai google anthropic deepseek])
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

    it "allows setting providers" do
      config.providers = %w[openai]
      expect(config.providers).to eq(%w[openai])
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
    it "does not share providers array between instances" do
      config_a = described_class.new
      config_b = described_class.new

      config_a.providers << "custom"

      expect(config_b.providers).not_to include("custom")
    end
  end
end
