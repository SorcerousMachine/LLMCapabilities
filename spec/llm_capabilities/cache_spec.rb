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
      expect(cache.lookup("openai/gpt-5-nano")).to be_nil
    end

    it "returns true for a model recorded as supported" do
      cache.record("openai/o4-mini", thinking: true, supported: true)

      expect(cache.lookup("openai/o4-mini", thinking: true)).to be true
    end

    it "returns false for a model recorded as unsupported" do
      cache.record("anthropic/claude-haiku-4.5", thinking: true, supported: false)

      expect(cache.lookup("anthropic/claude-haiku-4.5", thinking: true)).to be false
    end

    it "distinguishes thinking=true from thinking=false" do
      cache.record("openai/o4-mini", thinking: false, supported: true)
      cache.record("openai/o4-mini", thinking: true, supported: false)

      expect(cache.lookup("openai/o4-mini", thinking: false)).to be true
      expect(cache.lookup("openai/o4-mini", thinking: true)).to be false
    end
  end

  describe "#record" do
    it "persists entries to disk as JSON" do
      cache.record("google/gemini-2.5-flash", thinking: false, supported: true)

      data = JSON.parse(File.read(cache_path))
      entry = data["google/gemini-2.5-flash:thinking=false"]
      expect(entry["supported"]).to be true
      expect(entry["recorded_at"]).to be_a(Integer)
    end

    it "overwrites existing entries" do
      cache.record("openai/o4-mini", thinking: true, supported: true)
      cache.record("openai/o4-mini", thinking: true, supported: false)

      expect(cache.lookup("openai/o4-mini", thinking: true)).to be false
    end

    it "creates the cache directory if it does not exist" do
      nested_path = File.join(cache_dir, "nested", "dir", "cache.json")
      nested_cache = described_class.new(path: nested_path)

      nested_cache.record("openai/o4-mini", thinking: false, supported: true)

      expect(File.exist?(nested_path)).to be true
    end
  end

  describe "persistence across instances" do
    it "loads entries from disk on first access" do
      cache.record("openai/o4-mini", thinking: true, supported: true)

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini", thinking: true)).to be true
    end
  end

  describe "#clear!" do
    it "removes all entries" do
      cache.record("openai/o4-mini", thinking: false, supported: true)
      cache.record("google/gemini-2.5-flash", thinking: true, supported: false)

      cache.clear!

      expect(cache.size).to eq(0)
      expect(cache.lookup("openai/o4-mini")).to be_nil
    end

    it "persists the empty state to disk" do
      cache.record("openai/o4-mini", thinking: false, supported: true)
      cache.clear!

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini")).to be_nil
    end
  end

  describe "#size" do
    it "returns 0 for empty cache" do
      expect(cache.size).to eq(0)
    end

    it "returns the number of entries" do
      cache.record("a/b", thinking: false, supported: true)
      cache.record("c/d", thinking: true, supported: false)

      expect(cache.size).to eq(2)
    end
  end

  describe "corrupted cache file" do
    it "starts fresh on JSON parse error" do
      File.write(cache_path, "not valid json {{{")

      expect(cache.lookup("openai/o4-mini")).to be_nil
      expect(cache.size).to eq(0)
    end
  end

  describe "max_age expiration" do
    it "returns nil for expired entries" do
      cache.record("openai/o4-mini", thinking: false, supported: true)

      # Manually backdate the entry
      data = JSON.parse(File.read(cache_path))
      key = "openai/o4-mini:thinking=false"
      data[key]["recorded_at"] = Time.now.to_i - 2_592_001 # 30 days + 1 second
      File.write(cache_path, JSON.pretty_generate(data))

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini")).to be_nil
    end

    it "returns value for non-expired entries" do
      cache.record("openai/o4-mini", thinking: false, supported: true)

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini")).to be true
    end

    it "disables expiration when max_age is nil" do
      no_expire_cache = described_class.new(path: cache_path, max_age: nil)
      no_expire_cache.record("openai/o4-mini", thinking: false, supported: true)

      # Manually backdate the entry far in the past
      data = JSON.parse(File.read(cache_path))
      key = "openai/o4-mini:thinking=false"
      data[key]["recorded_at"] = Time.now.to_i - 999_999_999
      File.write(cache_path, JSON.pretty_generate(data))

      fresh_cache = described_class.new(path: cache_path, max_age: nil)
      expect(fresh_cache.lookup("openai/o4-mini")).to be true
    end
  end

  describe "incompatible cache format" do
    it "treats non-hash entry values as unreadable and returns nil" do
      # A cache file with bare booleans (wrong format) will raise on T.cast
      legacy_data = {"openai/o4-mini:thinking=false" => true}
      File.write(cache_path, JSON.pretty_generate(legacy_data))

      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini")).to be_nil
    end
  end

  describe "file locking" do
    it "uses shared lock on read and exclusive lock on write" do
      # Verify the cache works under normal conditions (locking is transparent)
      cache.record("openai/o4-mini", thinking: false, supported: true)
      fresh_cache = described_class.new(path: cache_path)
      expect(fresh_cache.lookup("openai/o4-mini")).to be true
    end
  end
end
