% tinyrox says don't edit this manually, but it can't stop you!
\name{llm_key}
\alias{llm_key}
\title{Set LLM API Key}
\usage{
llm_key(key)
}
\arguments{
\item{key}{Character. API key for authentication.}
}
\value{
The previous value of the option, invisibly.
}
\description{
Stores an API key in the \code{llm.api.api_key} option, which
\code{\link{chat}} prefers over environment variables.
}
\examples{
old <- llm_key("sk-not-a-real-key")
llm_key(old)  # restore
}
