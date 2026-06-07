% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_openai_codex}
\alias{chat_openai_codex}
\title{Chat with OpenAI Codex}
\usage{
chat_openai_codex(prompt, model = "gpt-5.5", ...)
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
Convenience wrapper for ChatGPT subscription-backed Codex models.
}
\examples{
\dontrun{
creds <- openai_codex_login()
chat_openai_codex("Write a small R function", credentials = creds)
}
}
