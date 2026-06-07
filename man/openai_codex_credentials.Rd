% tinyrox says don't edit this manually, but it can't stop you!
\name{openai_codex_credentials}
\alias{openai_codex_credentials}
\title{OpenAI Codex subscription credentials}
\usage{
openai_codex_credentials(access_token = Sys.getenv("OPENAI_CODEX_ACCESS_TOKEN", ""),
                         refresh_token = Sys.getenv("OPENAI_CODEX_REFRESH_TOKEN", ""),
                         expires_at = .openai_codex_env_number("OPENAI_CODEX_EXPIRES_AT"),
                         account_id = Sys.getenv("OPENAI_CODEX_ACCOUNT_ID", ""))
}
\arguments{
\item{access_token}{OAuth access token. If omitted, read from
\code{OPENAI_CODEX_ACCESS_TOKEN}.}

\item{refresh_token}{OAuth refresh token. If omitted, read from
\code{OPENAI_CODEX_REFRESH_TOKEN}.}

\item{expires_at}{Expiry time as a Unix timestamp in seconds, or
NULL if unknown.}

\item{account_id}{ChatGPT account id. Usually extracted from the
access token.}
}
\value{
A zero-argument credentials function returning request headers.
}
\description{
Creates a zero-argument credentials function suitable for the
OpenAI Codex provider. If a refresh token is supplied, the access
token is refreshed automatically when needed.
By default, credentials are read from:
\itemize{
\item \code{OPENAI_CODEX_ACCESS_TOKEN}
\item \code{OPENAI_CODEX_REFRESH_TOKEN}
\item \code{OPENAI_CODEX_EXPIRES_AT} (Unix timestamp, seconds)
\item \code{OPENAI_CODEX_ACCOUNT_ID}
}
}
