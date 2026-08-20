# Moonshot (Kimi) provider-native web search.
#
# Unlike the OpenAI Responses / Anthropic Messages search tools -- which run
# entirely server-side in a single call -- Moonshot's `$web_search` is a
# `builtin_function` that round-trips through the tool-call protocol: the model
# emits a `$web_search` tool call carrying a `search_id`, the client echoes the
# call's arguments straight back as the tool result, and the server runs the
# search and continues. So enabling web search on Moonshot means driving that
# echo loop internally rather than gating it on the caller's `tool_handler`.
#
# Two limitations of Moonshot's design, surfaced honestly:
#   * The search query isn't exposed in the tool-call arguments, so each
#     recorded search carries `query = NA` (only that a search happened).
#   * Citations are inlined into the answer text as markdown links; there is
#     no structured citations field, so `citations` comes back empty.

# Once-per-session warning state for ignored options.
.moonshot_state <- new.env(parent = emptyenv())

# The Moonshot `$web_search` builtin tool from the provider-neutral toggle, or
# NULL when off. The tool takes no options (no domain filters / user location /
# max_uses), so any supplied options are ignored with a one-time warning.
.moonshot_web_search_tool <- function(ws) {
    if (is.null(ws) || isFALSE(ws)) {
        return(NULL)
    }
    if (is.list(ws)) {
        ignored <- intersect(c("max_uses", "allowed_domains",
                               "blocked_domains", "user_location"), names(ws))
        if (length(ignored) &&
            is.null(.moonshot_state$warned_web_search_opts)) {
            .moonshot_state$warned_web_search_opts <- TRUE
            warning("Moonshot $web_search ignores ", paste(ignored,
                    collapse = ", "),
                    " (the builtin search tool has no such option). ",
                    "(Shown once per session.)", call. = FALSE)
        }
    }
    list(type = "builtin_function", `function` = list(name = "$web_search"))
}

# Is this parsed tool call Moonshot's builtin web search?
.is_moonshot_web_search <- function(tc) {
    identical(tc$name, "$web_search")
}

# The tool-result content to echo for a `$web_search` call: the call's own
# arguments, verbatim. The agent loop hands us parsed arguments (a list), so
# re-serialize them; the search_id inside is what the server keys on.
.moonshot_web_search_echo <- function(arguments) {
    # as.character() strips the "json" class so this lands as a JSON *string*
    # in the tool message, not a re-embedded JSON object.
    as.character(jsonlite::toJSON(arguments, auto_unbox = TRUE))
}

.moonshot_headers <- function(config) {
    headers <- c("Content-Type" = "application/json")
    if (!is.null(config$api_key) && nzchar(config$api_key)) {
        headers["Authorization"] <- paste("Bearer", config$api_key)
    }
    headers
}

# chat() with Moonshot web search. Drives the `$web_search` echo loop to
# completion and returns the final assistant text plus the search record. No
# user tools are involved (chat() passes only the builtin), so the only tool
# calls seen are `$web_search`; any other finish ends the loop.
.chat_moonshot_websearch <- function(body, config, stream) {
    url <- paste0(config$base_url, config$chat_path)
    headers <- .moonshot_headers(config)
    ws_tool <- .moonshot_web_search_tool(body$web_search)

    messages <- .llm_blocks(body$messages, "openai")
    searches <- list()
    # Cap round-trips so a misbehaving backend can't loop forever.
    for (i in seq_len(10L)) {
        req <- list(model = body$model, messages = messages,
                    tools = list(ws_tool))
        if (!is.null(body$temperature)) {
            req$temperature <- body$temperature
        }
        if (!is.null(body$max_tokens)) {
            req$max_tokens <- body$max_tokens
        }
        resp <- .post_json(url, req, headers)
        choice <- resp$choices[[1L]]
        msg <- choice$message
        ws_calls <- Filter(function(tc) identical(tc$`function`$name,
                "$web_search"), msg$tool_calls %||% list())

        if (length(ws_calls) == 0L) {
            content <- msg$content %||% ""
            thinking <- msg$reasoning_content %||% msg$reasoning
            .warn_if_truncated(content, thinking, choice$finish_reason)
            if (isTRUE(stream) && nzchar(content)) {
                cat(content, "\n", sep = "")
            }
            return(list(content = content, thinking = thinking,
                        finish_reason = choice$finish_reason,
                        usage = resp$usage, citations = list(),
                        searches = searches))
        }

        # Echo the assistant message, then each search call's arguments back as
        # its tool result so the server runs the search and continues.
        messages <- c(messages, list(msg))
        for (tc in ws_calls) {
            searches[[length(searches) + 1L]] <- list(query = NA_character_,
                status = "completed")
            messages <- c(messages, list(list(role = "tool",
                        tool_call_id = tc$id, name = "$web_search",
                        content = tc$`function`$arguments)))
        }
    }
    stop("Moonshot web search did not converge after 10 round-trips.",
         call. = FALSE)
}
