# frozen_string_literal: true

require "json"
require "tmpdir"

RSpec.describe LLMCapabilities::Cache do
  let(:cache_dir) { Dir.mktmpdir }
  let(:cache_path) { File.join(cache_dir, ".schema_cache.json") }
  subject(:cache) { described_class.new(path: cache_path) }

  after do
    FileUtils.rm_rf(cache_dir)
  end

  describe "#lookup" do
    it "returns nil for unknown model" do
      expect(cache.lookup("openai/gpt-5-nano", :structured_output)).to be_nil
    end

    it "returns true for a model recorded as supported" do
      cache.record("openai/o4-mini", :structured_output, context: {thinking: true}, supported: true)

      expect(cache.lookup("openai/o4-mini", :structured_output, context: {thinking: true})).to be true
    end

    it "returns false for a model recorded as unsupported" do
      cache.record("anthropic/claude-haiku-4.5", :structured_output, context: {thinking: true}, supported: false)

      expect(cache.lookup("anthropic/claude-haiku-4.5", :structured_output, context: {thinking: true})).to be false
    end

    it "distinguishes different context values" do
      cache.record("openai/o4-mini", :structured_output, context: {thinking: false}, supported: true)
      cache.record("openai/o4-mini", :structured_output, context: {thinking: true}, supported: false)

      expect(cache.lookup("openai/o4-mini", :structured_output, context: {thinking: false})).to be true
      expect(cache.lookup("openai/o4-mini", :structured_output, context: {thinking: true})).to be false
    end

    it "distinguishes different capabilities" do
      cache.record("openai/o4-mini", :structured_output, supported: true)
      cache.record("openai/o4-mini", :vision, supported: false)

      expect(cache.lookup("openai/o4-mini", :structured_output)).to be true
      expect(cache.lookup("openai/o4-mini", :vision)).to be false
    end
  end

  describe "#record" do
    it "persists entries to disk as JSON" do
      cache.record("google/gemini-2.5-flash", :structured_output, supported: true)

      data = JSON.parse(File.read(cache_path))
      entry = data["google/gemini-2.5-flash:structured_output"]
      expect(entry["supported"]).to be true
      expect(entry["recorded_at"]).to be_a(Integer)
    end

    it "overwrites existing entries" do
      cache.record("openai/o4-mini", :structured_output, context: {thinking: true}, supported: true)
      cache.record("openai/o4-mini", :structured_output, context: {thinking: true}, supported: false)

      expect(cache.lookup("openai/o4-mini", :structured_output, context: {thinking: true})).to be false
    end

    it "creates the cache directory if it does not exist" do
      nested_path = File.join(cache_dir, "nested", "dir", "cache.json")
      nested_cache = described_class.new(path: nested_path)

      nested_cache.record("openai/o4-mini", :structured_output, supported: true)

      expect(File.exist?(nested_path)).to be true
    end
  end

  describe "cache key format" do
    it "uses model:capability for no context" do
      cache.record("openai/o4-mini", :structured_output, supported: true)

      data = JSON.parse(File.read(cache_path))
      expect(data).to have_key("openai/o4-mini:structured_output")
    end

    it "uses model:capability:key=value for context" do
      cache.record("openai/o4-mini", :structured_output, context: {thinking: true}, supported: true)

      data = JSON.parse(File.read(cache_path))
      expect(data).to have_key("openai/o4-mini:structured_output:thinking=true")
    end

    it "sorts context keys alphabetically" do
      cache.record("openai/o4-mini", :structured_output, context: {z_param: "a", a_param: "b"}, supported: true)

      data = JSON.parse(File.read(cache_path))
      expect(data).to have_key("openai/o4-mini:structured_output:a_param=b,z_param=a")
    end

    it "produces same key regardless of hash insertion order" do
      cache.record("openai/o4-mini", :structured_output, context: {b: 1, a: 2}, supported: true)

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini", :structured_output, context: {a: 2, b: 1})).to be true
    end

    it "empty context produces same key as no context" do
      cache.record("openai/o4-mini", :vision, supported: true)

      expect(cache.lookup("openai/o4-mini", :vision, context: {})).to be true
    end
  end

  describe "persistence across instances" do
    it "loads entries from disk on first access" do
      cache.record("openai/o4-mini", :structured_output, context: {thinking: true}, supported: true)

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini", :structured_output, context: {thinking: true})).to be true
    end
  end

  describe "#clear!" do
    it "removes all entries" do
      cache.record("openai/o4-mini", :structured_output, supported: true)
      cache.record("google/gemini-2.5-flash", :vision, supported: false)

      cache.clear!

      expect(cache.size).to eq(0)
      expect(cache.lookup("openai/o4-mini", :structured_output)).to be_nil
    end

    it "persists the empty state to disk" do
      cache.record("openai/o4-mini", :structured_output, supported: true)
      cache.clear!

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini", :structured_output)).to be_nil
    end
  end

  describe "#size" do
    it "returns 0 for empty cache" do
      expect(cache.size).to eq(0)
    end

    it "returns the number of entries" do
      cache.record("a/b", :structured_output, supported: true)
      cache.record("c/d", :vision, context: {thinking: true}, supported: false)

      expect(cache.size).to eq(2)
    end
  end

  describe "corrupted cache file" do
    it "starts fresh on JSON parse error" do
      File.write(cache_path, "not valid json {{{")

      expect(cache.lookup("openai/o4-mini", :structured_output)).to be_nil
      expect(cache.size).to eq(0)
    end
  end

  describe "max_age expiration" do
    it "returns nil for expired entries" do
      cache.record("openai/o4-mini", :structured_output, supported: true)

      # Manually backdate the entry
      data = JSON.parse(File.read(cache_path))
      key = "openai/o4-mini:structured_output"
      data[key]["recorded_at"] = Time.now.to_i - 2_592_001 # 30 days + 1 second
      File.write(cache_path, JSON.pretty_generate(data))

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini", :structured_output)).to be_nil
    end

    it "returns value for non-expired entries" do
      cache.record("openai/o4-mini", :structured_output, supported: true)

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini", :structured_output)).to be true
    end

    it "disables expiration when max_age is nil" do
      no_expire_cache = described_class.new(path: cache_path, max_age: nil)
      no_expire_cache.record("openai/o4-mini", :structured_output, supported: true)

      # Manually backdate the entry far in the past
      data = JSON.parse(File.read(cache_path))
      key = "openai/o4-mini:structured_output"
      data[key]["recorded_at"] = Time.now.to_i - 999_999_999
      File.write(cache_path, JSON.pretty_generate(data))

      fresh_cache = described_class.new(path: cache_path, max_age: nil)
      expect(fresh_cache.lookup("openai/o4-mini", :structured_output)).to be true
    end
  end

  describe "incompatible cache format" do
    it "treats non-hash entry values as unreadable and returns nil" do
      legacy_data = {"openai/o4-mini:structured_output" => true}
      File.write(cache_path, JSON.pretty_generate(legacy_data))

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini", :structured_output)).to be_nil
    end
  end

  describe "file locking" do
    it "uses shared lock on read and exclusive lock on write" do
      cache.record("openai/o4-mini", :structured_output, supported: true)
      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini", :structured_output)).to be true
    end
  end
end
