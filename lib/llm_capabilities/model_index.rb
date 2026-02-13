# frozen_string_literal: true

require "json"
require "fileutils"
require "net/http"
require "uri"

module LLMCapabilities
  class ModelIndex
    OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models"

    # Mapping from OpenRouter field values to gem capability symbols.
    # NOTE: Name divergences are intentional and subtle:
    #   - OpenRouter "structured_outputs" (plural) -> gem :structured_output (singular)
    #   - OpenRouter "tools" -> gem :function_calling
    #   - OpenRouter "response_format" -> gem :json_mode
    #   - OpenRouter "reasoning" -> gem :reasoning
    PARAMETER_MAPPING = {
      "structured_outputs" => :structured_output,
      "tools" => :function_calling,
      "reasoning" => :reasoning,
      "response_format" => :json_mode
    }.freeze

    def initialize(path:, ttl:)
      @path = path
      @ttl = ttl
      @index = nil
    end

    def lookup(model, capability)
      load_index!
      model_caps = @index[model]
      return nil unless model_caps

      model_caps[capability]
    end

    private

    def load_index!
      return unless @index.nil?

      if File.exist?(@path) && !stale?
        load_from_disk
        return unless @index.nil?
      end

      fetch_and_cache!
    rescue => _e
      @index ||= {}
    end

    def stale?
      mtime = File.mtime(@path)
      (Time.now - mtime) > @ttl
    end

    def load_from_disk
      File.open(@path, File::RDONLY) do |f|
        f.flock(File::LOCK_SH)
        raw = JSON.parse(f.read)
        @index = deserialize(raw)
      end
    rescue JSON::ParserError
      @index = nil
    end

    def fetch_and_cache!
      uri = URI.parse(OPENROUTER_MODELS_URL)
      response = Net::HTTP.get_response(uri)

      unless response.is_a?(Net::HTTPSuccess)
        @index ||= {}
        return
      end

      raw_data = JSON.parse(response.body)
      @index = normalize(raw_data)
      persist!
    rescue => _e
      @index ||= {}
    end

    def normalize(raw_data)
      result = {}
      models = raw_data["data"]
      return result unless models.is_a?(Array)

      models.each do |model_entry|
        next unless model_entry.is_a?(Hash)

        id = model_entry["id"]
        next unless id.is_a?(String)

        caps = map_capabilities(model_entry)
        result[id] = caps unless caps.empty?
      end

      result
    end

    def map_capabilities(model_entry)
      caps = {}

      # Map supported_parameters to capabilities
      # NOTE: OpenRouter uses different names than the gem:
      #   "structured_outputs" (plural) -> :structured_output (singular)
      #   "tools" -> :function_calling
      #   "response_format" -> :json_mode
      params = model_entry["supported_parameters"]
      if params.is_a?(Array)
        params.each do |param|
          cap = PARAMETER_MAPPING[param]
          caps[cap] = true if cap
        end
      end

      # Map architecture modalities to capabilities
      arch = model_entry["architecture"]
      if arch.is_a?(Hash)
        input_mods = arch["input_modalities"]
        if input_mods.is_a?(Array) && input_mods.include?("image")
          caps[:vision] = true
        end

        output_mods = arch["output_modalities"]
        if output_mods.is_a?(Array) && output_mods.include?("image")
          caps[:image_generation] = true
        end
      end

      caps
    end

    def persist!
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

      serialized = serialize(@index)
      File.open(@path, File::CREAT | File::WRONLY | File::TRUNC) do |f|
        f.flock(File::LOCK_EX)
        f.write(JSON.pretty_generate(serialized))
      end
    end

    def serialize(index)
      index.transform_values { |caps| caps.transform_keys(&:to_s) }
    end

    def deserialize(raw)
      result = {}
      raw.each do |model_id, caps|
        next unless caps.is_a?(Hash)

        result[model_id] = caps.each_with_object({}) do |(k, v), acc|
          acc[k.to_sym] = v if v == true || v == false
        end
      end
      result
    end
  end
end
