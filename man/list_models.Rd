% tinyrox says don't edit this manually, but it can't stop you!
\name{list_models}
\alias{list_models}
\title{List provider model identifiers}
\usage{
list_models(provider, base_url = NULL, timeout = 5, codex_cache = NULL)
}
\arguments{
\item{provider}{Provider name.}

\item{base_url}{Optional endpoint override, with the same convention as
\code{\link{llm_base}}.}

\item{timeout}{Request timeout in seconds.}

\item{codex_cache}{Optional Codex model-cache path. Defaults to
\code{models_cache.json} under \code{CODEX_HOME} or \code{~/.codex}.}
}
\value{
Character vector of model identifiers. The \code{source} attribute
  is \code{"provider"} or \code{"Codex cache"}.
}
\description{
Queries the provider's model catalog without generating a response.
OpenAI Codex reads the local Codex model cache instead; those entries
reflect its last refresh, not a new entitlement check. Catalog membership
does not guarantee tool support. Unsupported catalogs raise an error so
callers can fall back to their configured models.
}
\examples{
\dontrun{
list_models("openai")
list_models("openai_codex")
}
}
