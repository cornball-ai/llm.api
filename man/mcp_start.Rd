% tinyrox says don't edit this manually, but it can't stop you!
\name{mcp_start}
\alias{mcp_start}
\title{Start and connect to an MCP server}
\usage{
mcp_start(command, args = character(), port = NULL, name = NULL,
          startup_wait = 2)
}
\arguments{
\item{command}{Character. Command to run the server (e.g., "r", "Rscript").}

\item{args}{Character vector. Arguments (path to server script).}

\item{port}{Integer. Port for the server (default: random 7850-7899).}

\item{name}{Character. Friendly name.}

\item{startup_wait}{Numeric. Seconds to wait for server startup.}
}
\value{
An MCP connection object.
}
\description{
Spawns an MCP server process and connects to it.
Requires the server script to support --port argument.
}
