% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_claude_oauth}
\alias{chat_claude_oauth}
\title{Chat with Claude on a subscription (OAuth)}
\usage{
chat_claude_oauth(prompt, model = "claude-sonnet-4-6", ...)
}
\arguments{
\item{prompt}{Character. The user message to send.}

\item{model}{Character. Model name (e.g., "gpt-5.4-mini", "claude-sonnet-4-6", "qwen3.5:9b").}

\item{...}{Additional parameters passed to the API.}
}
\value{
The assistant's response as a list. See \code{\link{chat}}.
}
\description{
Convenience wrapper for Claude-subscription-backed models via the OAuth
token from \code{\link{claude_oauth_login}} (no API key required).
}
\examples{
\dontrun{
claude_oauth_login()
chat_claude_oauth("Explain the theory of relativity")
}
}
