## Test environments

* Local: Ubuntu 24.04, R 4.5.3
* GitHub Actions: macos-latest, ubuntu-latest

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Notes

This package provides a minimal-dependency client for several LLM HTTP APIs
(OpenAI, Anthropic, Moonshot, Ollama) plus an agent loop with tool use and
a Model Context Protocol client. The only required dependencies are `curl`
and `jsonlite`.

API design is derived from the `ellmer` package, reimplemented in base R
with minimal dependencies. The `ellmer` team is credited as a copyright
holder in `Authors@R`.

Examples that hit live APIs are wrapped in `\dontrun{}` to avoid network
calls during checks.
