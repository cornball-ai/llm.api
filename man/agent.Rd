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
  provider = c("anthropic", "anthropic_claude", "openai", "moonshot", "openai_codex",
    "ollama", "openai_compatible"),
  max_turns = 20L,
  verbose = TRUE,
  history = NULL,
  history_callback = NULL,
  cache = c("none", "5m", "1h"),
  thinking_budget_tokens = NULL,
  web_search = FALSE,
  on_delta = NULL,
  ...
)
}
\arguments{
\item{prompt}{Character. The user message.}

\item{tools}{List. Tool definitions (from mcp_tools_for_claude or manual).}

\item{tool_handler}{Function. Called with `(name, args)` and returns a
result string. If it declares a formal named `context`, it also
receives (by name) a read-only per-call snapshot with `assistant_text` (the model's
text for this turn), `agent_turn`, `call_index`, `call_count`, and
`provider`; two-argument handlers are called unchanged.}

\item{system}{Character. System prompt.}

\item{model}{Character. Model name.}

\item{provider}{Character. Provider: "anthropic", "anthropic_claude", "openai", "moonshot",
"openai_codex", "ollama", or "openai_compatible" (a generic
OpenAI-compatible gateway; requires a base URL via
\code{llm_base()} or \code{OPENAI_COMPATIBLE_BASE_URL}, and an
explicit \code{model}).}

\item{max_turns}{Integer. Maximum tool-use turns (default: 20).}

\item{verbose}{Logical. Print tool calls and results.}

\item{history}{List or NULL. Previous conversation history to continue from.}

\item{history_callback}{Function or NULL. Called as
\code{history_callback(history)} after each assistant message is
appended and after each tool result is appended. Lets callers
snapshot intermediate state so an interrupt mid-turn doesn't lose
the work that was already done. Errors raised inside the callback
are swallowed so telemetry/snapshotting can't break a turn.}

\item{cache}{Character. Anthropic prompt caching for the system
message: \code{"none"} (default), \code{"5m"}, or \code{"1h"}
ephemeral TTL. Anthropic-only; warns and degrades to \code{"none"}
for other providers.}

\item{thinking_budget_tokens}{Integer or NULL. Anthropic extended
thinking budget; must be at least 1024 and less than
\code{max_tokens}. Anthropic-only; ignored with a warning for
other providers.}

\item{web_search}{Enable provider-native (server-side) web search:
\code{FALSE} (default), \code{TRUE}, or a list of options
(\code{allowed_domains}, \code{user_location}). Server-side, so it is
not gated by \code{tool_handler}; the result accumulates
\code{citations} and \code{searches} across turns. Wired for
\code{"openai_codex"} and \code{"openai"} (OpenAI Responses
\code{web_search} tool; for \code{"openai"} the run is routed through
the Responses endpoint), \code{"anthropic"},
\code{"anthropic_claude"}, and \code{"moonshot"}
(the \code{$web_search} builtin, whose calls are handled internally
rather than via \code{tool_handler}); ignored with a warning
otherwise.}

\item{on_delta}{Function or NULL. Called with each fragment of the
model's text as it arrives, before the response is complete, so a
caller can start displaying or speaking it. Called many times per
turn, with a single non-empty character scalar each time; its
return value is ignored.

Calling \code{\link{llm_cancel}} from inside it abandons the
request: the connection closes, the provider stops generating, and
\code{agent()} returns immediately with \code{cancelled = TRUE} and
whatever text had arrived. The assistant message is not appended to
\code{history} in that case, because a partial one can carry an
unmatched tool call that breaks the following request; the caller
knows what was delivered and records it.

Wired for every provider except \code{"anthropic"} and
\code{"anthropic_claude"}, whose Messages API request is not
streamed yet; passing it there warns and is ignored rather than
silently doing nothing.}

\item{...}{Additional parameters passed to the API.}
}
\value{
List with final response and conversation history. The
  returned \code{$usage} carries cumulative \code{input_tokens},
  \code{output_tokens}, \code{total_tokens}, and \code{cost} (USD
  scalar, derived from the bundled price snapshot; \code{0} for
  Ollama; \code{NA_real_} for models not in the snapshot). It also
  carries cumulative cache activity: \code{cache_read_input_tokens}
  (Anthropic cache reads plus OpenAI/Moonshot cached prompt tokens),
  \code{cache_creation_input_tokens} (total Anthropic cache writes),
  and the per-TTL split \code{cache_creation$ephemeral_5m_input_tokens}
  / \code{cache_creation$ephemeral_1h_input_tokens}. Passing this
  \code{$usage} back to \code{\link{usage_cost}} recomputes the same
  \code{cost}.
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
