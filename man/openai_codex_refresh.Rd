% tinyrox says don't edit this manually, but it can't stop you!
\name{openai_codex_refresh}
\alias{openai_codex_refresh}
\title{Refresh an OpenAI Codex OAuth token}
\usage{
openai_codex_refresh(refresh_token = Sys.getenv("OPENAI_CODEX_REFRESH_TOKEN", ""))
}
\arguments{
\item{refresh_token}{OAuth refresh token. Defaults to
\code{OPENAI_CODEX_REFRESH_TOKEN}.}
}
\value{
A list with \code{access}, \code{refresh}, \code{expires},
  and \code{account_id}.
}
\description{
Refresh an OpenAI Codex OAuth token
}
