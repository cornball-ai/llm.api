% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_session_openai}
\alias{chat_session_openai}
\title{Create OpenAI chat session}
\usage{
chat_session_openai(model = "gpt-4o", system_prompt = NULL, ...)
}
\arguments{
\item{model}{Character. Model name (default: "gpt-4o").}

\item{system_prompt}{Character or NULL. System prompt.}

\item{...}{Additional parameters passed to chat_session().}
}
\value{
A chat session list.
}
\description{
Convenience wrapper for chat_session with OpenAI provider.
}
