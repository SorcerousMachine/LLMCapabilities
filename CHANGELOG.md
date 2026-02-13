# Changelog

## 0.2.0

- Generalize API from `supports_schema?(model, thinking:)` to `supports?(model, capability, context: {})`
- Add 4-tier resolution hierarchy: empirical cache, OpenRouter model index, RubyLLM registry, provider heuristic
- Add `ModelIndex` class for unauthenticated OpenRouter `/api/v1/models` integration
- Add 18 validated capability symbols (`KNOWN_CAPABILITIES`) with `UnknownCapabilityError`
- Add freeform context hash for cache precision (e.g., `{thinking: true}`)
- Remove `sorbet-runtime` dependency (zero runtime dependencies)

## 0.1.0

- Initial release: 3-tier structured output detection (cache, RubyLLM, provider heuristic)
