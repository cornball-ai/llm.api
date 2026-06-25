## Test environments

* Local: Ubuntu 24.04, R 4.6.0
* Local: Windows 10 x64, R 4.6.0 (release)
* Local: Windows 10 x64, R-devel (R 4.7.0 ucrt)

## R CMD check results

0 errors | 0 warnings | 0 notes

`R CMD check --as-cran` is clean across all three environments above.

## Release summary

Update to 0.1.7 (last CRAN release: 0.1.4), consolidating three
post-release development cycles (0.1.5, 0.1.6, 0.1.6.1), none of which
were submitted to CRAN. All changes are backwards-compatible: new
exported functions and new optional parameters that default to existing
behaviour.

* New `openai_codex` provider for ChatGPT-subscription-backed Codex
  (OpenAI Responses API): `chat_openai_codex()`, `agent(provider =
  "openai_codex")`, `openai_codex_credentials()`, and
  `openai_codex_login()`. Device login, token refresh, and on-disk
  caching are handled by `tinyoauth` (>= 0.1.1).
* New `anthropic_claude` provider: drive Claude on a Claude subscription
  via OAuth (no API key), mirroring the `openai_codex` provider. Adds
  `chat_claude_oauth()`, `claude_oauth_login()`, and
  `anthropic_claude_credentials()`. Login, token caching, and refresh
  run through tinyoauth's Claude route; the request path is shared with
  the API-key `anthropic` provider.
* Provider-native web search: a `web_search` argument on `chat()` and
  `agent()`, wired for all four hosted providers (OpenAI, Anthropic,
  Moonshot, and Codex). When on, the result carries `citations` and
  `searches`.
* `agent()` passes a read-only per-call `context` snapshot (by name) to
  a `tool_handler` that declares a `context` formal. Two-argument
  handlers are called exactly as before, so this is fully backwards
  compatible.

## Notes

This package is a minimal-dependency client for several LLM (Large
Language Model) HTTP APIs (OpenAI, Anthropic, Moonshot, Ollama) plus
an agent loop with tool use and a Model Context Protocol client. The
only required dependencies remain `curl`, `jsonlite`, and `tinyoauth`
(now on CRAN).

API design is derived from the `ellmer` package; the `ellmer` team is
credited as a copyright holder in `Authors@R`. Examples that hit live
APIs are wrapped in `\dontrun{}` to avoid network calls during checks.

## Downstream dependencies

CRAN reverse dependency: `corteza`. No other CRAN reverse
dependencies. The 0.1.7 changes are additive (new providers, new
exports, optional parameters), so the current CRAN `corteza` is
unaffected; a reverse-dependency check is run before submission.
