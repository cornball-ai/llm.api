% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_openai}
\alias{chat_openai}
\title{Chat with OpenAI}
\usage{
chat_openai(prompt, model = "gpt-4o-mini", ...)
}
\arguments{
\item{prompt}{Character. The user message to send.}

\item{model}{Character. Model name (e.g., "gpt-4o", "claude-sonnet-4-6", "llama3.2").}

\item{...}{Additional parameters passed to the API.}
}
\value{
The assistant's response as a character string, or a list when
  \code{history} is in use. See \code{\link{chat}} for details.
}
\description{
Convenience wrapper for 'OpenAI' models.
}
\examples{
\dontrun{
chat_openai("Explain quantum computing")
chat_openai("Write a haiku", model = "gpt-4o")
}
}
