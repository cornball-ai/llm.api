% tinyrox says don't edit this manually, but it can't stop you!
\name{history_tool_calls}
\alias{history_tool_calls}
\title{Walk a history list and return paired tool-call / tool-result records.}
\usage{
history_tool_calls(history)
}
\arguments{
\item{history}{List of messages, typically the `history` element
from an [agent()] return value.}
}
\value{
A list of tool-call records (possibly empty). Records are
  returned in the order calls were issued.
}
\description{
Accepts either a `history` list as returned by [agent()] (in which
case every entry is treated as a message) or any list-of-messages
that follows the same shape. Returns a list of records, one per
tool call, each with:
\describe{
\item{id}{Canonical call id (synthesized for Ollama responses
that omit one).}
\item{name}{Tool name.}
\item{arguments}{Argument list. Parsed from JSON for OpenAI-style
shapes; passed through for Anthropic.}
\item{result}{Tool result text, or `NULL` if the call has no
matching result yet.}
\item{completed}{`TRUE` when `result` is non-`NULL`.}
\item{call_message_index}{1-based index of the assistant message
that issued the call.}
\item{result_message_index}{1-based index of the message
carrying the result, or `NA_integer_` for unfinished calls.}
\item{provider_shape}{`"anthropic"` or `"openai"`. Useful when a
consumer needs to branch on shape (rare).}
}
}
