% tinyrox says don't edit this manually, but it can't stop you!
\name{mcp_tools}
\alias{mcp_tools}
\title{List tools from an MCP connection}
\usage{
mcp_tools(conn)
}
\arguments{
\item{conn}{An MCP connection object.}
}
\value{
List of tool definitions.
}
\description{
List tools from an MCP connection
}
\examples{
\dontrun{
conn <- mcp_connect(port = 7850)
tools <- mcp_tools(conn)
mcp_close(conn)
}
}
