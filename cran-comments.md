## Release summary

Minor update, 0.1.9 -> 0.2.0. New features and fixes; no export is
removed and no existing argument changes meaning.

* New `google` provider: 'Google' 'Gemini' through its
  OpenAI-compatible endpoint.
* Streaming on every provider: `agent()` gains `on_delta`, and
  `llm_cancel()` stops a response early. `chat(stream = TRUE)` was
  broken in 0.1.9 and is fixed.
* Image input: `llm_image()`, `llm_content()`, `llm_has_image()`.
* `list_models()` lists a provider's model identifiers.
* `agent()` gains `checkpoint_callback`, `request_callback`, and
  `thinking`; `chat()` gains `request_callback` and `thinking`. All are
  optional and default to the previous behavior.
* `agent()` no longer reports a response cut off at the output-token
  limit as a clean completion; it returns `truncated = TRUE`.
* Anthropic prompt caching covers the message history, and the bundled
  price snapshot is refreshed to 2026-11-02.
* The `openai` and `openai_codex` default model is now `gpt-6.1-sol`.
  The `anthropic` default is unchanged from 0.1.9.

## Test environments

* Local: Ubuntu 24.04, R 4.6.1
* win-builder: R 4.6.2 (2026-10-29 ucrt) and R-devel (2026-11-07 r90850
  ucrt)

## R CMD check results

0 errors | 0 warnings | 0 notes

## Notes

This package is a minimal-dependency client for several LLM (Large
Language Model) HTTP APIs plus an agent loop with tool use and a Model
Context Protocol client. The only required dependencies remain `curl`,
`jsonlite`, and `tinyoauth`.

API design is derived from the `ellmer` package; the `ellmer` team is
credited as a copyright holder in `Authors@R`. Examples that hit live
APIs are wrapped in `\dontrun{}` to avoid network calls during checks.
Tests make no network calls: transports are stubbed or read local
fixture files.

Nothing in the package writes outside `tempdir()`. The one function that
starts a subprocess, `mcp_start()`, is `\dontrun{}` and is not reached
from any test.

## Downstream dependencies

CRAN reverse dependencies: `corteza` 0.7.1 (reverse import) and `pensar`
0.7.0 (reverse suggest). Both were checked against this build in an
isolated library with `R CMD check`: both return Status: OK.
