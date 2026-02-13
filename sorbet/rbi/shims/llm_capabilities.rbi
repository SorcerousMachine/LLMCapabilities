# typed: true

module LLMCapabilities
  sig { returns(LLMCapabilities::Configuration) }
  def self.configuration; end

  sig { params(block: T.proc.params(arg0: LLMCapabilities::Configuration).void).void }
  def self.configure(&block); end

  sig { params(model: String, capability: Symbol, context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def self.supports?(model, capability, context: {}); end

  sig { params(model: String, capability: Symbol, supported: T::Boolean, context: T::Hash[Symbol, T.untyped]).void }
  def self.record(model, capability, supported:, context: {}); end

  sig { params(model: String, capability: Symbol, context: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Boolean)) }
  def self.lookup(model, capability, context: {}); end

  sig { void }
  def self.clear!; end

  sig { returns(Integer) }
  def self.size; end

  sig { void }
  def self.reset!; end

  sig { returns(LLMCapabilities::Cache) }
  private_class_method def self.cache; end

  sig { returns(LLMCapabilities::ModelIndex) }
  private_class_method def self.model_index; end

  sig { returns(LLMCapabilities::Detector) }
  private_class_method def self.detector; end

  class Error < StandardError; end
  class UnknownCapabilityError < Error; end

  class Configuration
    DEFAULT_CACHE_PATH = T.let("".freeze, String)
    DEFAULT_INDEX_PATH = T.let("".freeze, String)
    DEFAULT_INDEX_TTL = T.let(0, Integer)
    DEFAULT_MAX_AGE = T.let(0, Integer)
    DEFAULT_PROVIDER_CAPABILITIES = T.let({}.freeze, T::Hash[Symbol, T::Array[String]])

    sig { returns(String) }
    def cache_path; end

    sig { params(value: String).returns(String) }
    def cache_path=(value); end

    sig { returns(String) }
    def index_path; end

    sig { params(value: String).returns(String) }
    def index_path=(value); end

    sig { returns(Integer) }
    def index_ttl; end

    sig { params(value: Integer).returns(Integer) }
    def index_ttl=(value); end

    sig { returns(T::Hash[Symbol, T::Array[String]]) }
    def provider_capabilities; end

    sig { params(value: T::Hash[Symbol, T::Array[String]]).returns(T::Hash[Symbol, T::Array[String]]) }
    def provider_capabilities=(value); end

    sig { returns(Integer) }
    def max_age; end

    sig { params(value: Integer).returns(Integer) }
    def max_age=(value); end

    sig { void }
    def initialize; end
  end

  class Cache
    sig { params(path: String, max_age: Integer).void }
    def initialize(path: Configuration::DEFAULT_CACHE_PATH, max_age: Configuration::DEFAULT_MAX_AGE); end

    sig { params(model: String, capability: Symbol, context: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Boolean)) }
    def lookup(model, capability, context: {}); end

    sig { params(model: String, capability: Symbol, supported: T::Boolean, context: T::Hash[Symbol, T.untyped]).void }
    def record(model, capability, supported:, context: {}); end

    sig { void }
    def clear!; end

    sig { returns(Integer) }
    def size; end

    private

    sig { params(model: String, capability: Symbol, context: T::Hash[Symbol, T.untyped]).returns(String) }
    def cache_key(model, capability, context); end

    sig { void }
    def load_cache!; end

    sig { void }
    def persist!; end
  end

  class ModelIndex
    OPENROUTER_MODELS_URL = T.let("".freeze, String)
    PARAMETER_MAPPING = T.let({}.freeze, T::Hash[String, Symbol])

    sig { params(path: String, ttl: Integer).void }
    def initialize(path:, ttl:); end

    sig { params(model: String, capability: Symbol).returns(T.nilable(T::Boolean)) }
    def lookup(model, capability); end

    private

    sig { void }
    def load_index!; end

    sig { returns(T::Boolean) }
    def stale?; end

    sig { void }
    def load_from_disk; end

    sig { void }
    def fetch_and_cache!; end

    sig { params(raw_data: T::Hash[String, T.untyped]).returns(T::Hash[String, T::Hash[Symbol, T::Boolean]]) }
    def normalize(raw_data); end

    sig { params(model_entry: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T::Boolean]) }
    def map_capabilities(model_entry); end

    sig { void }
    def persist!; end

    sig { params(index: T::Hash[String, T::Hash[Symbol, T::Boolean]]).returns(T::Hash[String, T::Hash[String, T::Boolean]]) }
    def serialize(index); end

    sig { params(raw: T::Hash[String, T.untyped]).returns(T::Hash[String, T::Hash[Symbol, T::Boolean]]) }
    def deserialize(raw); end
  end

  class Detector
    KNOWN_CAPABILITIES = T.let([], T::Array[Symbol])

    sig do
      params(
        cache: LLMCapabilities::Cache,
        provider_capabilities: T::Hash[Symbol, T::Array[String]],
        model_index: T.nilable(LLMCapabilities::ModelIndex),
        ruby_llm_enabled: T.nilable(T::Boolean)
      ).void
    end
    def initialize(cache:, provider_capabilities: Configuration::DEFAULT_PROVIDER_CAPABILITIES, model_index: nil, ruby_llm_enabled: nil); end

    sig { params(model: String, capability: Symbol, context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def supports?(model, capability, context: {}); end

    sig { params(model: String, capability: Symbol).returns(T::Boolean) }
    def provider_supports?(model, capability); end

    private

    sig { params(capability: Symbol).void }
    def validate_capability!(capability); end

    sig { returns(T::Boolean) }
    def ruby_llm_available?; end

    sig { params(model: String, capability: Symbol).returns(T.nilable(T::Boolean)) }
    def query_ruby_llm(model, capability); end
  end
end
