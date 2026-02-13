# llm_capabilities

[![CI](https://github.com/SorcerousMachine/LLMCapabilities/actions/workflows/ci.yml/badge.svg)](https://github.com/SorcerousMachine/LLMCapabilities/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/llm_capabilities)](https://rubygems.org/gems/llm_capabilities)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

4-tier capability detection for LLM models. Zero runtime dependencies.

Answers the question: *does this model support this capability?* — using a layered resolution hierarchy that combines empirical observations, live model indexes, and static heuristics.

## Resolution Hierarchy

Each query walks four tiers in order. The first non-nil result wins.

| Tier | Source | What it knows |
|------|--------|---------------|
| 1 | **Empirical cache** | Observed results from actual API calls, with optional context (e.g., `{thinking: true}`) |
| 2 | **OpenRouter model index** | Per-model capability data from OpenRouter's public API, cached locally for 24 hours |
| 3 | **RubyLLM model registry** | Soft dependency — used automatically when the `ruby_llm` gem is loaded |
| 4 | **Provider heuristic** | Static fallback mapping providers to known capabilities |

Tier 1 is the most authoritative because it reflects what you've actually observed. Tiers 2-4 provide progressively coarser defaults.

## Quick Start

```ruby
gem "llm_capabilities"
```

```ruby
require "llm_capabilities"

# Query a capability (walks all 4 tiers automatically)
LLMCapabilities.supports?("openai/o4-mini", :structured_output)
# => true

LLMCapabilities.supports?("deepseek/deepseek-r1", :vision)
# => false

# Query with context (only matches tier 1 cache entries with the same context)
LLMCapabilities.supports?("anthropic/claude-haiku-4.5", :structured_output, context: { thinking: true })
# => false (if you've recorded that specific combination as unsupported)
```

Model identifiers use the `"provider/model"` format (e.g., `"openai/gpt-4o"`, `"anthropic/claude-sonnet-4.5"`).

## Recording Empirical Results

The real power is in tier 1: recording what you've actually observed from API calls.

```ruby
# After a successful structured output call
LLMCapabilities.record("openai/o4-mini", :structured_output, supported: true)

# After discovering a model doesn't support a capability in a specific context
LLMCapabilities.record(
  "anthropic/claude-haiku-4.5",
  :structured_output,
  context: { thinking: true },
  supported: false
)

# Look up a cached result directly (nil if not recorded)
LLMCapabilities.lookup("openai/o4-mini", :structured_output)
# => true

# Cache management
LLMCapabilities.size   # => 2
LLMCapabilities.clear! # wipes all cached entries
```

Cache entries are persisted to disk as JSON and survive process restarts. Entries expire after 30 days by default.

## Configuration

```ruby
LLMCapabilities.configure do |config|
  # File paths for persistent storage
  config.cache_path = ".llm_capabilities_cache.json"  # default
  config.index_path = ".llm_capabilities_index.json"   # default

  # Cache entry lifetime (seconds)
  config.max_age = 2_592_000  # 30 days, default

  # OpenRouter index refresh interval (seconds)
  config.index_ttl = 86_400   # 24 hours, default

  # Override which providers support which capabilities
  config.provider_capabilities = {
    structured_output: %w[openai google anthropic deepseek],
    function_calling:  %w[openai google anthropic deepseek],
    vision:            %w[openai google anthropic],
    streaming:         %w[openai google anthropic deepseek]
  }
end
```

## Known Capabilities

The gem recognizes 18 capability symbols. Passing anything else to `supports?` raises `LLMCapabilities::UnknownCapabilityError`.

| Capability | Description |
|------------|-------------|
| `:structured_output` | JSON schema-constrained output |
| `:function_calling` | Tool/function calling |
| `:vision` | Image input processing |
| `:streaming` | Streaming response support |
| `:json_mode` | JSON output mode (less strict than structured output) |
| `:reasoning` | Extended thinking / chain-of-thought |
| `:image_generation` | Image output generation |
| `:speech_generation` | Audio/speech output |
| `:transcription` | Audio-to-text conversion |
| `:translation` | Language translation |
| `:citations` | Source citation support |
| `:predicted_outputs` | Predicted/cached output optimization |
| `:distillation` | Model distillation support |
| `:fine_tuning` | Fine-tuning API support |
| `:batch` | Batch API processing |
| `:realtime` | Real-time / WebSocket API |
| `:caching` | Prompt caching |
| `:moderation` | Content moderation |

## Default Provider Capabilities

Tier 4 uses these static mappings as a last resort when no better data is available:

| Capability | Providers |
|------------|-----------|
| `:structured_output` | openai, google, anthropic, deepseek |
| `:function_calling` | openai, google, anthropic, deepseek |
| `:vision` | openai, google, anthropic |
| `:streaming` | openai, google, anthropic, deepseek |

These can be overridden via `config.provider_capabilities`.

## OpenRouter API Usage

Tier 2 fetches model capability data from [OpenRouter's](https://openrouter.ai) unauthenticated public endpoint (`GET /api/v1/models`). This data is cached locally on disk with a 24-hour TTL. No API key is required. No data is sent to OpenRouter — it is a read-only GET request.

If the fetch fails (network error, timeout, non-200 response), tier 2 is silently skipped and resolution falls through to tiers 3 and 4. The gem never blocks on network failure.

See OpenRouter's [terms of service](https://openrouter.ai/terms) for their data usage policies.

## RubyLLM Integration

Tier 3 activates automatically when the [`ruby_llm`](https://github.com/crmne/ruby_llm) gem is loaded in your process. No configuration required — if `RubyLLM` is defined, the gem queries its model registry for capability data. If `ruby_llm` is not present, tier 3 is silently skipped.

## Requirements

- Ruby >= 3.2
- Zero runtime dependencies (stdlib only: `json`, `net/http`, `fileutils`)

## License

MIT. See [LICENSE.txt](LICENSE.txt).
