% tinyrox says don't edit this manually, but it can't stop you!
\name{mcp_connect}
\alias{mcp_connect}
\title{Connect to an MCP server}
\usage{
mcp_connect(host = "localhost", port, name = NULL, timeout = 30)
}
\arguments{
\item{host}{Character. Server hostname (default: "localhost").}

\item{port}{Integer. Server port.}

\item{name}{Character. Friendly name for this server.}

\item{timeout}{Numeric. Connection timeout in seconds (default: 30).}
}
\value{
An MCP connection object (list with socket and tools).
}
\description{
Connects to an MCP server via TCP socket.
}
\examples{
\dontrun{
# Start server first: r mcp_server.R --port 7850
conn <- mcp_connect(port = 7850, name = "codeR")
tools <- mcp_tools(conn)
result <- mcp_call(conn, "read_file", list(path = "README.md"))
mcp_close(conn)
}
}
