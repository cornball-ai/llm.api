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
* win-builder: R-devel and R-release

## R CMD check results

0 errors | 0 warnings | 1 note

### NOTE: Rd \usage line width

```
* checking Rd line widths ... NOTE
Rd file 'agent.Rd':
  \usage lines wider than 90 characters:
     provider = c("anthropic", "anthropic_claude", "openai", "moonshot",
     "openai_codex", "ollama", "openai_compatible"),
```

`agent()` and `create_agent()` document their `provider` choices in the
signature so `?agent` shows the full set. Adding `openai_compatible`
takes that vector to seven entries, and the documentation generator now
emits it as a single line instead of wrapping it as it did at six.

The alternative is to hide the choices behind a constant, which would
shorten the `\usage` line at the cost of removing the list of valid
providers from the rendered documentation. The signature and its
defaults are unchanged from 0.1.8 apart from the one added element, so
I have kept the self-documenting form. Happy to change it if the
reviewer would prefer.

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
