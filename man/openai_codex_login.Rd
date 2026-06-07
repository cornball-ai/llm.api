% tinyrox says don't edit this manually, but it can't stop you!
\name{openai_codex_login}
\alias{openai_codex_login}
\title{Log in to OpenAI Codex with a device-code flow}
\usage{
openai_codex_login(timeout = 600, open_url = interactive())
}
\arguments{
\item{timeout}{Maximum number of seconds to wait for login.}

\item{open_url}{Logical. Whether to open the verification URL in a browser.}
}
\value{
A zero-argument credentials function.
}
\description{
Runs tinyoauth's ChatGPT Codex device-login flow, caching the token for reuse
across sessions, and returns an \code{\link{openai_codex_credentials}}
callback.
}
