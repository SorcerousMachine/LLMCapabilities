# llm_capabilities

4-tier capability detection for LLM models. Zero runtime dependencies.

Detects whether LLM models support specific capabilities (structured output, vision, function calling, etc.) via a layered resolution hierarchy:

1. **Empirical cache** -- observed results from actual API calls, with optional context (e.g., `{thinking: true}`)
2. **OpenRouter model index** -- per-model capability data from OpenRouter's public API
3. **RubyLLM model registry** -- soft dependency, used when loaded
4. **Provider heuristic** -- static fallback mapping providers to capabilities

## OpenRouter API Usage

Tier 2 fetches model capability data from [OpenRouter's](https://openrouter.ai) unauthenticated public endpoint (`GET /api/v1/models`). This data is cached locally on disk with a 24-hour TTL. No API key is required. No data is sent to OpenRouter -- it is a read-only GET request.

If the fetch fails (network error, timeout, non-200 response), tier 2 is silently skipped and resolution falls through to tiers 3 and 4. The gem never blocks on network failure.

See OpenRouter's [terms of service](https://openrouter.ai/terms) for their data usage policies.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
