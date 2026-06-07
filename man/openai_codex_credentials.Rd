% tinyrox says don't edit this manually, but it can't stop you!
\name{openai_codex_credentials}
\alias{openai_codex_credentials}
\title{OpenAI Codex subscription credentials}
\usage{
openai_codex_credentials(access_token = Sys.getenv("OPENAI_CODEX_ACCESS_TOKEN", ""),
                         account_id = Sys.getenv("OPENAI_CODEX_ACCOUNT_ID", ""))
}
\arguments{
\item{access_token}{Optional access token. If omitted, read from
\code{OPENAI_CODEX_ACCESS_TOKEN}, then from the tinyoauth cache.}

\item{account_id}{Optional ChatGPT account id. If omitted, read from
\code{OPENAI_CODEX_ACCOUNT_ID}, then from the access-token JWT.}
}
\value{
A zero-argument credentials function returning request headers.
}
\description{
Builds a zero-argument credentials function for the OpenAI Codex provider.
Tokens are obtained, cached, and refreshed by tinyoauth (see
\code{\link[tinyoauth]{oauth_token_openai_codex}}); this returns the request
headers (\code{Authorization} and \code{chatgpt-account-id}) for the current
token.
}
\details{
Environment variables still override the cache when set:
\itemize{
\item \code{OPENAI_CODEX_ACCESS_TOKEN}
\item \code{OPENAI_CODEX_ACCOUNT_ID}
}

}
