## Test environments

* Local: Ubuntu 24.04, R 4.6.0
* win-builder: R-devel (R 4.7.0 ucrt)

## R CMD check results

0 errors | 0 warnings | 0 notes

`R CMD check --as-cran` is clean on Ubuntu 24.04 / R 4.6.0. The
immediately-preceding 0.1.7 tarball passed win-builder R-devel and
R-release; 0.1.8 adds only a one-line wire fix plus a test on top of it.

## Release summary

Patch update to 0.1.8 (last CRAN release: 0.1.4). This supersedes a
pending 0.1.7 submission (not yet published) with a one-line fix:
`anthropic_claude` agent runs with tool use now send a valid `messages`
array on the turn after a tool call (the agent loop drives the shared
Anthropic Messages wire for the subscription-OAuth provider). `chat()`
was unaffected.

0.1.8 also carries the 0.1.5-0.1.7 consolidation (new `openai_codex` and
`anthropic_claude` providers, provider-native web search, per-call tool
context), none of which were on CRAN. All changes are backwards-compatible:
new exported functions and new optional parameters that default to existing
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

CRAN reverse dependencies: `corteza` (reverse import) and `pensar`
(reverse suggest). The 0.1.7 changes are additive (new providers, new
exports, optional parameters), so the current CRAN `corteza` and
`pensar` are unaffected; a reverse-dependency check is run before
submission.
