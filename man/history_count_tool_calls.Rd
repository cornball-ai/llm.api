% tinyrox says don't edit this manually, but it can't stop you!
\name{history_count_tool_calls}
\alias{history_count_tool_calls}
\title{Count tool calls in a history list.}
\usage{
history_count_tool_calls(history, completed_only = FALSE)
}
\arguments{
\item{history}{List of messages.}

\item{completed_only}{Logical. When `TRUE`, count only calls whose
result is present in the history. Default `FALSE`.}
}
\value{
Single integer.
}
\description{
Thin convenience wrapper over [history_tool_calls()]. Pass
`completed_only = TRUE` to count only calls that have matching
results (i.e., to skip mid-flight calls at the end of a turn that
got cut off).
}
