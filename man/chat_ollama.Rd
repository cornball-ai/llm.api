% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_ollama}
\alias{chat_ollama}
\title{Chat with Ollama}
\usage{
chat_ollama(prompt, model = "llama3.2", ...)
}
\arguments{
\item{prompt}{Character. The user message to send.}

\item{model}{Character. Model name (e.g., "gpt-4o", "claude-3-5-sonnet-latest", "llama3.2").}

\item{...}{Additional parameters passed to the API.}
}
\description{
Convenience wrapper for local Ollama models.
}
\examples{
\dontrun{
chat_ollama("What is machine learning?")
chat_ollama("Explain Docker", model = "mistral")
}
}
