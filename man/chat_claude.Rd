% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_claude}
\alias{chat_claude}
\title{Chat with Anthropic Claude}
\usage{
chat_claude(prompt, model = "claude-3-5-sonnet-latest", ...)
}
\arguments{
\item{prompt}{Character. The user message to send.}

\item{model}{Character. Model name (e.g., "gpt-4o", "claude-3-5-sonnet-latest", "llama3.2").}

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
chat_claude("Write a poem", model = "claude-3-5-haiku-latest")
}
}
