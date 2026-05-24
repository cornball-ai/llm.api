% tinyrox says don't edit this manually, but it can't stop you!
\name{prices_snapshot_date}
\alias{prices_snapshot_date}
\title{Bundled price-snapshot date}
\usage{
prices_snapshot_date()
}
\value{
Character scalar in `YYYY-MM-DD` format.
}
\description{
`llm.api` estimates `usage$cost` from a model-price table baked into
the package at release time. This returns the date that bundled
table was generated.
}
\details{
It does not contact the network, check for newer prices, or update
the installed package. Use the date to display staleness warnings
(see [prices_snapshot_stale()]) or to decide when the package
maintainer should regenerate the snapshot for a future release.

The table is generated from BerriAI/litellm's
`model_prices_and_context_window.json`
(\url{https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json}).
Cost estimates are offline and approximate, and may differ from
current provider billing. Cached-input pricing follows each
provider's published model: OpenAI
(\url{https://platform.openai.com/docs/guides/prompt-caching}),
Moonshot (\url{https://www.kimi.com/help/kimi-api/api-pricing}), and
Anthropic
(\url{https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching}).

}
\examples{
prices_snapshot_date()
}
\seealso{
[prices_snapshot_stale()], [usage_cost()]
}
