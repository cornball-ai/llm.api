% tinyrox says don't edit this manually, but it can't stop you!
\name{anthropic_oauth_credentials}
\alias{anthropic_oauth_credentials}
\title{Anthropic Claude subscription (OAuth) credentials}
\usage{
anthropic_oauth_credentials(access_token = Sys.getenv("ANTHROPIC_OAUTH_ACCESS_TOKEN", ""))
}
\arguments{
\item{access_token}{Optional access token. If omitted, read from
\code{ANTHROPIC_OAUTH_ACCESS_TOKEN}, then from the tinyoauth cache.}
}
\value{
A zero-argument credentials function returning request headers.
}
\description{
Builds a zero-argument credentials function for the \code{anthropic_oauth}
provider. Tokens are obtained, cached, and refreshed by tinyoauth (see
\code{\link[tinyoauth]{oauth_token_anthropic}}); this returns the request
headers (\code{Authorization} and the OAuth beta header) for the current
token.
}
\details{
The \code{ANTHROPIC_OAUTH_ACCESS_TOKEN} environment variable overrides the
cache when set.

}
