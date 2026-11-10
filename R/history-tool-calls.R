# Helpers for walking the message history that agent() returns.
#
# `history` is provider-native by design: it's the sequence of messages
# we send back into the next API call, so the shape has to match what
# each provider expects on input. That means consumers walking history
# for tool-call introspection have to handle three distinct shapes:
#
#   Anthropic
#     assistant role, content = list of blocks, with
#       {type = "tool_use", id, name, input}
#     user role, content = list of blocks, with
#       {type = "tool_result", tool_use_id, content}
#
#   OpenAI / moonshot / ollama
#     assistant role, content = "" (or text), tool_calls = list of
#       {id, type = "function", function = {name, arguments}}
#     tool role, tool_call_id, name, content
#
#   OpenAI Responses (openai_codex, and openai on the Responses wire)
#     {type = ".openai_codex_output", output = list of items}, where a
#       call is an item {type = "function_call", call_id, name, arguments}
#     {type = "function_call_output", call_id, output}
#
# These helpers pair calls with their results and return a single
# canonical record list so consumers stop reinventing the walk.

#' Walk a history list and return paired tool-call / tool-result records.
#'
#' Accepts either a `history` list as returned by [agent()] (in which
#' case every entry is treated as a message) or any list-of-messages
#' that follows the same shape. Returns a list of records, one per
#' tool call, each with:
#'
#' \describe{
#'   \item{id}{Canonical call id (synthesized for Ollama responses
#'     that omit one).}
#'   \item{name}{Tool name.}
#'   \item{arguments}{Argument list. Parsed from JSON for OpenAI-style
#'     shapes; passed through for Anthropic.}
#'   \item{result}{Tool result text, or `NULL` if the call has no
#'     matching result yet.}
#'   \item{completed}{`TRUE` when `result` is non-`NULL`.}
#'   \item{call_message_index}{1-based index of the assistant message
#'     that issued the call.}
#'   \item{result_message_index}{1-based index of the message
#'     carrying the result, or `NA_integer_` for unfinished calls.}
#'   \item{provider_shape}{`"anthropic"`, `"openai"` (Chat Completions),
#'     or `"responses"` (the OpenAI Responses wire: `openai_codex`, and
#'     `openai` when [agent_uses_responses()] is TRUE). Useful when a
#'     consumer needs to branch on shape (rare).}
#' }
#'
#' @param history List of messages, typically the `history` element
#'   from an [agent()] return value.
#' @return A list of tool-call records (possibly empty). Records are
#'   returned in the order calls were issued.
#' @export
history_tool_calls <- function(history) {
    if (!is.list(history) || length(history) == 0L) {
        return(list())
    }

    # Pass 1: collect calls.
    calls <- list()
    for (i in seq_along(history)) {
        entry <- history[[i]]
        if (!is.list(entry)) {
            next
        }
        # Responses shape: one entry holds the turn's output items, and
        # each function_call item is a call.
        if (identical(entry$type, ".openai_codex_output")) {
            for (item in entry$output %||% list()) {
                if (!identical(item$type, "function_call")) {
                    next
                }
                calls[[length(calls) + 1L]] <- list(
                    id = item$call_id %||% item$id %||% "",
                    name = item$name %||% "",
                    arguments = tryCatch(
                        jsonlite::fromJSON(item$arguments %||% "{}",
                                           simplifyVector = FALSE),
                        error = function(e) list()),
                    result = NULL, completed = FALSE,
                    call_message_index = i,
                    result_message_index = NA_integer_,
                    provider_shape = "responses")
            }
            next
        }
        role <- entry$role %||% ""
        if (!identical(role, "assistant")) {
            next
        }

        cnt <- entry$content
        # Anthropic shape: content is a list of typed blocks.
        if (is.list(cnt)) {
            for (block in cnt) {
                if (identical(block$type %||% "", "tool_use")) {
                    calls[[length(calls) + 1L]] <- list(id = block$id %||% "",
                        name = block$name %||% "",
                        arguments = block$input %||% list(), result = NULL,
                        completed = FALSE, call_message_index = i,
                        result_message_index = NA_integer_,
                        provider_shape = "anthropic")
                }
            }
        }
        # OpenAI shape: separate tool_calls field on the assistant message.
        if (!is.null(entry$tool_calls)) {
            for (tc in entry$tool_calls) {
                fn <- tc$`function` %||% list()
                args_raw <- fn$arguments %||% list()
                args <- if (is.character(args_raw) && length(args_raw) == 1L) {
                    tryCatch(
                             jsonlite::fromJSON(args_raw, simplifyVector = FALSE),
                             error = function(e) list()
                    )
                } else {
                    args_raw
                }
                calls[[length(calls) + 1L]] <- list(
                    id = tc$id %||% "",
                    name = fn$name %||% "",
                    arguments = args,
                    result = NULL,
                    completed = FALSE,
                    call_message_index = i,
                    result_message_index = NA_integer_,
                    provider_shape = "openai"
                )
            }
        }
    }

    if (length(calls) == 0L) {
        return(list())
    }

    # Pass 2: pair results back to calls.
    for (i in seq_along(history)) {
        entry <- history[[i]]
        if (!is.list(entry)) {
            next
        }
        # Responses: each result is its own function_call_output entry.
        if (identical(entry$type, "function_call_output")) {
            target_id <- entry$call_id %||% ""
            if (!nzchar(target_id)) {
                next
            }
            result_text <- paste(as.character(entry$output %||% ""),
                                 collapse = "\n")
            for (j in seq_along(calls)) {
                if (!calls[[j]]$completed &&
                    identical(calls[[j]]$id, target_id)) {
                    calls[[j]]$result <- result_text
                    calls[[j]]$completed <- TRUE
                    calls[[j]]$result_message_index <- i
                    break
                }
            }
            next
        }
        role <- entry$role %||% ""

        # Anthropic: tool_result blocks live in user-role messages.
        if (identical(role, "user")) {
            cnt <- entry$content
            if (is.list(cnt)) {
                for (block in cnt) {
                    if (identical(block$type %||% "", "tool_result")) {
                        target_id <- block$tool_use_id %||% block$id %||% ""
                        if (!nzchar(target_id)) {
                            next
                        }
                        result_text <- .history_block_result_text(block)
                        for (j in seq_along(calls)) {
                            if (!calls[[j]]$completed &&
                                identical(calls[[j]]$id, target_id)) {
                                calls[[j]]$result <- result_text
                                calls[[j]]$completed <- TRUE
                                calls[[j]]$result_message_index <- i
                                break
                            }
                        }
                    }
                }
            }
            next
        }

        # OpenAI: each tool result is its own role="tool" message.
        if (identical(role, "tool")) {
            target_id <- entry$tool_call_id %||% entry$id %||% ""
            if (!nzchar(target_id)) {
                next
            }
            result_text <- as.character(entry$content %||% "")
            for (j in seq_along(calls)) {
                if (!calls[[j]]$completed &&
                    identical(calls[[j]]$id, target_id)) {
                    calls[[j]]$result <- result_text
                    calls[[j]]$completed <- TRUE
                    calls[[j]]$result_message_index <- i
                    break
                }
            }
        }
    }

    calls
}

#' Count tool calls in a history list.
#'
#' Thin convenience wrapper over [history_tool_calls()]. Pass
#' `completed_only = TRUE` to count only calls that have matching
#' results (i.e., to skip mid-flight calls at the end of a turn that
#' got cut off).
#'
#' @param history List of messages.
#' @param completed_only Logical. When `TRUE`, count only calls whose
#'   result is present in the history. Default `FALSE`.
#' @return Single integer.
#' @export
history_count_tool_calls <- function(history, completed_only = FALSE) {
    calls <- history_tool_calls(history)
    if (length(calls) == 0L) {
        return(0L)
    }
    if (isTRUE(completed_only)) {
        completed <- vapply(calls, function(c) isTRUE(c$completed), logical(1))
        return(as.integer(sum(completed)))
    }
    length(calls)
}

# ---- Internal helpers ----

# Anthropic tool_result blocks may be a flat string or a list of inner
# {type: "text"} blocks. Render to a single string.
.history_block_result_text <- function(block) {
    cnt <- block$content
    if (is.character(cnt)) {
        return(paste(cnt, collapse = "\n"))
    }
    if (is.list(cnt)) {
        parts <- vapply(cnt, function(b) {
            as.character(b$text %||% "")
        }, character(1))
        return(paste(parts, collapse = "\n"))
    }
    as.character(cnt %||% "")
}

# Note: `%||%` is defined in chat.R for the package; reused here.
