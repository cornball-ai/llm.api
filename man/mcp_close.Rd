% tinyrox says don't edit this manually, but it can't stop you!
\name{mcp_close}
\alias{mcp_close}
\title{Close an MCP connection}
\usage{
mcp_close(conn)
}
\arguments{
\item{conn}{An MCP connection object.}
}
\value{
\code{NULL}, invisibly. Called for its side effect of closing
  the underlying socket.
}
\description{
Close an MCP connection
}
