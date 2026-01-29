% tinyrox says don't edit this manually, but it can't stop you!
\name{agent}
\alias{agent}
\title{Chat with tool use (agentic mode)}
\usage{
agent(
  prompt,
  tools = list(),
  tool_handler = NULL,
  system = NULL,
  model = NULL,
  provider = c("anthropic", "openai", "ollama"),
  max_turns = 20L,
  verbose = TRUE,
  ...
)
}
\arguments{
\item{prompt}{Character. The user message.}

\item{tools}{List. Tool definitions (from mcp_tools_for_claude or manual).}

\item{tool_handler}{Function. Called with (name, args), returns result string.}

\item{system}{Character. System prompt.}

\item{model}{Character. Model name.}

\item{provider}{Character. Provider: "anthropic", "openai", "ollama".}

\item{max_turns}{Integer. Maximum tool-use turns (default: 20).}

\item{verbose}{Logical. Print tool calls and results.}

\item{...}{Additional parameters passed to the API.}
}
\value{
List with final response and conversation history.
}
\description{
Send a prompt to an LLM with tools. Automatically handles tool calls
in a loop until the model responds with text only.
}
\examples{
\dontrun{
# With MCP server
conn <- mcp_connect("r", "mcp_server.R")
tools <- mcp_tools_for_claude(conn)

result <- agent(
  "What files are in the current directory?",
  tools = tools,
  tool_handler = function(name, args) {
    mcp_call(conn, name, args)$text
  }
)
}
}
