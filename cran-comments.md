## Release summary

Patch update, 0.1.8 -> 0.1.9. One new feature and two small fixes, all
backwards-compatible.

* New `openai_compatible` provider: point `chat()`, `agent()`, and
  `chat_session()` at any OpenAI-compatible gateway (OpenRouter,
  DeepSeek, corporate proxies). The base URL comes from `llm_base()` or
  `OPENAI_COMPATIBLE_BASE_URL`; the key from `llm_key()`,
  `OPENAI_COMPATIBLE_API_KEY`, or `OPENAI_API_KEY`, and a keyless
  gateway is supported (no Authorization header is sent). Model ids pass
  through untouched and are required. A missing base URL or model fails
  fast with instructions rather than a curl error.
* `agent()`'s OpenAI-wire request omits the `Authorization` header when
  no key is configured, matching `chat()`, so keyless gateways no longer
  receive a bare "Bearer " header.
* The endpoint and key options are renamed to `llm.api_base` and
  `llm.api_key`, matching the sibling API packages. `llm_base()` and
  `llm_key()` are unchanged, and the previous names
  (`llm.api.api_base` / `llm.api.api_key`) are still read as a fallback
  with a one-time deprecation warning per session.

## Test environments

* Local: Ubuntu 24.04, R 4.5.3
* Windows 10: R 4.6.0 and R-devel (2026-07-21 r90286 ucrt)

## R CMD check results

0 errors | 0 warnings | 0 notes

## On the 0.1.8 NOTE for r-devel-linux-x86_64-debian-gcc

The published 0.1.8 carries a "new files in some other directories"
NOTE on that one flavour, listing 119 `~/tmp/scratch/Rtmp*` directories
and 39 `~/tmp/scratch/xvfb-run.*` files.

Those are not this package's. llm.api has no graphics code and never
invokes a display server, so it cannot produce an `xvfb-run` file, and a
full check opens a handful of R sessions rather than 119. `~/tmp/scratch`
is that builder's shared `TMPDIR`, and the check appears to be
attributing debris left by concurrent checks. No other flavour reports
it.

Nothing in the package writes outside `tempdir()`. The one function that
starts a subprocess, `mcp_start()`, is `\dontrun{}` and is not reached
from any test.

## Notes

This package is a minimal-dependency client for several LLM (Large
Language Model) HTTP APIs (OpenAI, Anthropic, Moonshot, Ollama, and now
any OpenAI-compatible gateway) plus an agent loop with tool use and a
Model Context Protocol client. The only required dependencies remain
`curl`, `jsonlite`, and `tinyoauth`.

API design is derived from the `ellmer` package; the `ellmer` team is
credited as a copyright holder in `Authors@R`. Examples that hit live
APIs are wrapped in `\dontrun{}` to avoid network calls during checks.

## Downstream dependencies

CRAN reverse dependencies: `corteza` (reverse import) and `pensar`
(reverse suggest). This release is additive (one new provider, no
removed or changed exports), so both are unaffected. A
reverse-dependency check is run before submission.
