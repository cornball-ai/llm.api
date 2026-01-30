% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_session_anthropic}
\alias{chat_session_anthropic}
\title{Create Anthropic chat session}
\usage{
chat_session_anthropic(
  model = "claude-sonnet-4-20250514",
  system_prompt = NULL,
  ...
)
}
\arguments{
\item{model}{Character. Model name (default: "claude-sonnet-4-20250514").}

\item{system_prompt}{Character or NULL. System prompt.}

\item{...}{Additional parameters passed to chat_session().}
}
\value{
A chat session list.
}
\description{
Convenience wrapper for chat_session with Anthropic provider.
}
