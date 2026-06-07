% tinyrox says don't edit this manually, but it can't stop you!
\name{usage_cost}
\alias{usage_cost}
\title{Estimate the USD cost of one call's token usage}
\usage{
usage_cost(model, provider, usage)
}
\arguments{
\item{model}{Character. Model id as sent to the provider.}

\item{provider}{Character. "anthropic", "openai", "moonshot",
"openai_codex", or "ollama".}

\item{usage}{A usage list as found in `chat()$usage` or
`agent()$usage`.}
}
\value{
Numeric scalar (USD), or `NA_real_` when `usage` is `NULL`,
  the model isn't in the snapshot, or cache reads can't be priced.
}
\description{
Computes the offline cost estimate for a usage object, the same
value `chat()` and `agent()` attach as `usage$cost`. Reads whichever
shape the provider returned (Anthropic's `input_tokens` /
`output_tokens`, or the OpenAI-compatible `prompt_tokens` /
`completion_tokens`) and accounts for prompt caching: Anthropic
cache writes/reads via published multipliers, OpenAI / Moonshot
cache hits at the bundled per-model `cache_read` rate. OpenAI cache
hits are read from `prompt_tokens_details$cached_tokens` on a raw
response, falling back to a flat `cache_read_input_tokens` field as
exposed by `agent()` aggregates, so an `agent()$usage` object
recomputes to the same cost it already carries.
Costs come from the bundled price snapshot, so they are offline,
approximate, and may differ from current provider billing. See
[prices_snapshot_date()].
}
\examples{
\dontrun{
r <- chat("hi", model = "claude-sonnet-4-6", cache = "5m")
usage_cost("claude-sonnet-4-6", "anthropic", r$usage)
}
}
