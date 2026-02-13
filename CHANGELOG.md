# Changelog

## 0.2.1

- Add CI workflow, Codecov coverage reporting, and GitHub Actions gem release
- Add comprehensive README with badges, API reference, and capability tables
- Add SimpleCov with 95% minimum coverage enforcement (141 tests, 99.56% line coverage)
- Add Rakefile for gem release task

## 0.2.0

- Generalize API from `supports_schema?(model, thinking:)` to `supports?(model, capability, context: {})`
- Add 4-tier resolution hierarchy: empirical cache, OpenRouter model index, RubyLLM registry, provider heuristic
- Add `ModelIndex` class for unauthenticated OpenRouter `/api/v1/models` integration
- Add 18 validated capability symbols (`KNOWN_CAPABILITIES`) with `UnknownCapabilityError`
- Add freeform context hash for cache precision (e.g., `{thinking: true}`)
- Remove `sorbet-runtime` dependency (zero runtime dependencies)

## 0.1.0

- Initial release: 3-tier structured output detection (cache, RubyLLM, provider heuristic)
