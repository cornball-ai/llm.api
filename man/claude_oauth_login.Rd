% tinyrox says don't edit this manually, but it can't stop you!
\name{claude_oauth_login}
\alias{claude_oauth_login}
\title{Log in to Claude with the subscription OAuth flow}
\usage{
claude_oauth_login(open_url = interactive())
}
\arguments{
\item{open_url}{Logical. Whether to open the authorization URL in a browser.}
}
\value{
A zero-argument credentials function, invisibly. You don't normally
  need it: the cached token is picked up automatically by
  \code{chat(provider = "anthropic_claude")} and \code{chat_claude_oauth()}.
}
\description{
Runs tinyoauth's Claude (Claude Code) login flow, caching the token for reuse
across sessions, and returns an \code{\link{anthropic_claude_credentials}}
callback. The login is manual-paste: open the printed URL, approve, and paste
the displayed code back.
}
