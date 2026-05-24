## Test environments

* Local: Ubuntu 24.04, R 4.6.0
* Local: Windows 10 x64, R 4.6.0 (release)
* Local: Windows 10 x64, R-devel (R 4.7.0 ucrt)

## R CMD check results

0 errors | 0 warnings | 0 notes

`R CMD check --as-cran` is clean across all three environments above.

## Release summary

Patch update to 0.1.4 (last CRAN release: 0.1.3), consolidating five
post-release development cycles (0.1.3.1 -> 0.1.3.5). All changes are
backwards-compatible: new exported functions and new optional
parameters that default to existing behaviour.

* Cache-aware cost estimates. The bundled per-token price snapshot
  (from BerriAI/litellm's `model_prices_and_context_window.json`,
  shipped in `R/sysdata.rda`; no internet access at install or check
  time) now also carries per-model cached-input rates. New exported
  `usage_cost()` prices a usage object including prompt caching, and
  `chat()` / `agent()` carry the estimate as `usage$cost`.
* New exported `prices_snapshot_stale()` reports whether the bundled
  snapshot is older than a threshold, for staleness alerts.
* `chat()` / `agent()` gain `cache` (Anthropic prompt caching) and
  `thinking_budget_tokens` (Anthropic extended thinking) parameters,
  both Anthropic-only and no-ops elsewhere. OpenAI requests map
  `max_tokens` to `max_completion_tokens`.
* `agent()` gains a `history_callback` for snapshotting intermediate
  state, and aggregates cache token usage into its returned `$usage`.
* Default models per provider refreshed to current, snapshot-priceable
  ids.

The snapshot regeneration script is in `data-raw/prices.R` and is
excluded from the built tarball via `.Rbuildignore`.

## Notes

This package is a minimal-dependency client for several LLM (Large
Language Model) HTTP APIs (OpenAI, Anthropic, Moonshot, Ollama) plus
an agent loop with tool use and a Model Context Protocol client. The
only required dependencies remain `curl` and `jsonlite`.

API design is derived from the `ellmer` package; the `ellmer` team is
credited as a copyright holder in `Authors@R`. Examples that hit live
APIs are wrapped in `\dontrun{}` to avoid network calls during checks.

## Downstream dependencies

CRAN reverse dependency: `corteza`. No other CRAN reverse
dependencies. The 0.1.4 changes are additive (new exports and optional
parameters), so `corteza` is unaffected; a reverse-dependency check
against the current CRAN `corteza` is run before submission.
