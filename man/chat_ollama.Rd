% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_ollama}
\alias{chat_ollama}
\title{Chat with Ollama}
\usage{
chat_ollama(prompt, model = "llama3.2", ...)
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
Convenience wrapper for local 'Ollama' models.
}
\examples{
\dontrun{
chat_ollama("What is machine learning?")
chat_ollama("Explain Docker", model = "mistral")
}
}
