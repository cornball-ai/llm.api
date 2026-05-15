## Test environments

* Local: Ubuntu 24.04, R 4.5.3
* Local: Windows 10 x64, R 4.6.0 (release)
* Local: Windows 10 x64, R-devel (R 4.7.0 ucrt, gcc 14.3.0)
* GitHub Actions: macos-latest, ubuntu-latest

## R CMD check results

0 errors | 0 warnings | 0 notes

Identical clean result across all environments above, including
`R CMD check --as-cran --no-manual` on the Windows hosts.

## Release summary

Minor update to 0.1.3 (last CRAN release: 0.1.1).

* New `$usage$cost` field on `chat()` and `agent()` returns, derived
  from a bundled per-token price snapshot. The snapshot is taken from
  BerriAI/litellm's `model_prices_and_context_window.json` (the same
  upstream the `ellmer` package uses) and ships in `R/sysdata.rda`;
  no internet access at install or check time. Regeneration script
  is in `data-raw/prices.R` and is excluded from the built tarball
  via `.Rbuildignore`.
* New exported helpers `history_tool_calls()`,
  `history_count_tool_calls()`, `provider_default_model()`, and
  `prices_snapshot_date()`.
* `chat()` now surfaces `$thinking` (reasoning-model chain-of-thought)
  and `$finish_reason`, normalized across providers.
* `agent()` writes synthesized tool-call ids back into Ollama
  assistant messages so call/result pairing in history is consistent.

## Notes

This package is a minimal-dependency client for several LLM HTTP APIs
(OpenAI, Anthropic, Moonshot, Ollama) plus an agent loop with tool use
and a Model Context Protocol client. The only required dependencies
remain `curl` and `jsonlite`.

API design is derived from the `ellmer` package; the `ellmer` team is
credited as a copyright holder in `Authors@R`. Examples that hit live
APIs are wrapped in `\dontrun{}` to avoid network calls during checks.

## Downstream dependencies

CRAN reverse dependency: `corteza`. No other CRAN reverse
dependencies. `R CMD check` on `corteza` 0.6.3 (the current CRAN
release) against `llm.api` 0.1.3 was clean (Status: OK).
