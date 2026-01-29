% tinyrox says don't edit this manually, but it can't stop you!
\name{mcp_tools_for_api}
\alias{mcp_tools_for_api}
\title{Format MCP tools for LLM APIs}
\usage{
mcp_tools_for_api(conn)
}
\arguments{
\item{conn}{An MCP connection, or list of connections.}
}
\value{
List of tools in API format.
}
\description{
Converts MCP tool definitions to the format used by Claude/OpenAI.
}
