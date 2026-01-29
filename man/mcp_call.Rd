% tinyrox says don't edit this manually, but it can't stop you!
\name{mcp_call}
\alias{mcp_call}
\title{Call a tool on an MCP server}
\usage{
mcp_call(conn, name, arguments = list())
}
\arguments{
\item{conn}{An MCP connection object.}

\item{name}{Character. Tool name.}

\item{arguments}{List. Tool arguments.}
}
\value{
Tool result (list with content and text).
}
\description{
Call a tool on an MCP server
}
