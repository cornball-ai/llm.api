% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_claude}
\alias{chat_claude}
\title{Chat with Anthropic Claude}
\usage{
chat_claude(prompt, model = "claude-sonnet-4-6", ...)
}
\arguments{
\item{prompt}{Character. The user message to send.}

\item{model}{Character. Model name (e.g., "gpt-5.4-mini", "claude-sonnet-4-6", "qwen3.5:9b").}

\item{...}{Additional parameters passed to the API.}
}
\value{
The assistant's response as a character string, or a list when
  \code{history} is in use. See \code{\link{chat}} for details.
}
\description{
Convenience wrapper for 'Anthropic' 'Claude' models.
}
\examples{
\dontrun{
chat_claude("Explain the theory of relativity")
chat_claude("Write a poem", model = "claude-haiku-4-5")
}
}
