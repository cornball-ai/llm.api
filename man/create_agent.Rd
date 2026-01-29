% tinyrox says don't edit this manually, but it can't stop you!
\name{create_agent}
\alias{create_agent}
\title{Create an agent with MCP servers}
\usage{
create_agent(
  servers = list(),
  system = NULL,
  model = NULL,
  provider = c("anthropic", "openai", "ollama"),
  verbose = TRUE
)
}
\arguments{
\item{servers}{Named list of server configs. Each can be:
- `list(port = 7850)` for already-running servers
- `list(command = "r", args = "server.R", port = 7850)` to start and connect}

\item{system}{Character. Default system prompt.}

\item{model}{Character. Default model.}

\item{provider}{Character. Provider: "anthropic", "openai", "ollama".}

\item{verbose}{Logical. Print tool calls.}
}
\value{
A function that takes a prompt and returns a response.
}
\description{
Convenience function that sets up MCP connections and returns
a function for chatting with tools.
}
\examples{
\dontrun{
# Connect to already-running server
chat_fn <- create_agent(
  servers = list(codeR = list(port = 7850)),
  system = "You are a helpful coding assistant."
)

# Or start server automatically
chat_fn <- create_agent(
  servers = list(
    codeR = list(command = "r", args = "mcp_server.R", port = 7850)
  )
)

result <- chat_fn("List files in current directory")
}
}
