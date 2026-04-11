% tinyrox says don't edit this manually, but it can't stop you!
\name{mcp_tools_for_claude}
\alias{mcp_tools_for_claude}
\title{Format MCP tools for Claude API}
\usage{
mcp_tools_for_claude(conn)
}
\arguments{
\item{conn}{An MCP connection, or list of connections.}
}
\value{
List of tools in API format.
}
\description{
Wrapper for \code{\link{mcp_tools_for_api}}, retained for backwards
compatibility.
}
\examples{
\dontrun{
conn <- mcp_connect(host = "localhost", port = 7850)
tools <- mcp_tools_for_claude(conn)
mcp_close(conn)
}
}
