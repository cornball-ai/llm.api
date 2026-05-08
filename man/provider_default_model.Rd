% tinyrox says don't edit this manually, but it can't stop you!
\name{provider_default_model}
\alias{provider_default_model}
\title{Default model for a provider}
\usage{
provider_default_model(provider)
}
\arguments{
\item{provider}{Character. One of `"openai"`, `"anthropic"`,
`"moonshot"`, `"ollama"`.}
}
\value{
Character. The default model id for that provider.
}
\description{
Returns the model name `chat()` falls back to when the caller
doesn't specify one. Useful for client code that wants to display
the resolved model upfront (e.g., in a status line) without
duplicating the lookup table.
}
\examples{
provider_default_model("anthropic")
provider_default_model("moonshot")
}
