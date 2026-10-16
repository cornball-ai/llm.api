% tinyrox says don't edit this manually, but it can't stop you!
\name{agent_uses_responses}
\alias{agent_uses_responses}
\title{Check whether an agent request uses Responses}
\usage{
agent_uses_responses(
  provider,
  model = NULL,
  tools = list(),
  web_search = FALSE,
  history = NULL
)
}
\arguments{
\item{provider}{Provider name.}

\item{model}{Model identifier, or NULL for the provider default.}

\item{tools}{Tool schemas, as passed to \code{agent}.}

\item{web_search}{Search setting, as passed to \code{agent}.}

\item{history}{Conversation history, as passed to \code{agent}.}
}
\value{
Logical scalar. TRUE for the Codex provider, or for OpenAI when
  search, GPT-6 tools, or an existing Responses history selects Responses.
}
\description{
Reports the routing decision used by \code{\link{agent}} without a
request or credential lookup. Hosts can use it before offering tools that
require a particular history format. This describes the wire, not the
model's availability or permission to use it.
}
\examples{
agent_uses_responses("openai", "gpt-6-astra", tools = list(list(name = "lookup")))
agent_uses_responses("openai", "gpt-5.5", web_search = FALSE)
}
