% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_session_openai_codex}
\alias{chat_session_openai_codex}
\title{Create OpenAI Codex chat session}
\usage{
chat_session_openai_codex(model = "gpt-5.5", system_prompt = NULL, ...)
}
\arguments{
\item{model}{Character. Model name (default: "gpt-5.5").}

\item{system_prompt}{Character or NULL. System prompt.}

\item{...}{Additional parameters passed to chat_session().}
}
\value{
A chat session list.
}
\description{
Convenience wrapper for chat_session with the OpenAI Codex provider.
}
\examples{
\dontrun{
session <- chat_session_openai_codex()
session$chat("Hello")
}
}
