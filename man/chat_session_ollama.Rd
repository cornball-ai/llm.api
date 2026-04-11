% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_session_ollama}
\alias{chat_session_ollama}
\title{Create Ollama chat session}
\usage{
chat_session_ollama(model = "llama3.2", system_prompt = NULL, ...)
}
\arguments{
\item{model}{Character. Model name (default: "llama3.2").}

\item{system_prompt}{Character or NULL. System prompt.}

\item{...}{Additional parameters passed to chat_session().}
}
\value{
A chat session list.
}
\description{
Convenience wrapper for chat_session with Ollama provider.
}
\examples{
# Construct a session (no network call yet)
session <- chat_session_ollama(system_prompt = "You are helpful.")
\dontrun{
session$chat("Hello")
}
}
