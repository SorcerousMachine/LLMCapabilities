# frozen_string_literal: true

require_relative "lib/llm_capabilities/version"

Gem::Specification.new do |spec|
  spec.name = "llm_capabilities"
  spec.version = LLMCapabilities::VERSION
  spec.authors = ["Alex"]
  spec.summary = "4-tier capability detection for LLM models"
  spec.description = "Detects whether LLM models support specific capabilities via empirical cache, " \
    "OpenRouter model index, RubyLLM model registry, and provider-level heuristics. Zero runtime dependencies."
  spec.homepage = "https://github.com/alexfarrill/llm_capabilities"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  # Zero runtime dependencies — stdlib only (json, net/http, fileutils)
end
