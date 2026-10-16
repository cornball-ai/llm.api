# Standard OpenAI Responses API path (provider = "openai")
#
# The chat-completions endpoint (/v1/chat/completions) can't run server-side
# web search on the default models -- `web_search_options` needs a dedicated
# `-search-preview` model. The Responses endpoint (/v1/responses) takes the
# same {type:"web_search"} tool the Codex backend does and runs it on ordinary
# models (gpt-5.x, etc.), so web search "just works" on the default model.
#
# This reuses the generic Responses helpers that happen to carry an
# `.openai_codex_` prefix (SSE merge, output parse, message->input conversion,
# the web_search tool builder); only the URL, auth (a plain bearer key instead
# of a ChatGPT account id), and body defaults differ from the Codex path. So
# GPT-6 agent tool calls use this endpoint even when web search is off.

.openai_requires_responses_tools <- function(model) {
    isTRUE(grepl("^gpt-(?:[6-9]|[1-9][0-9]+)(?:[.-]|$)", model, perl = TRUE))
}

.openai_responses_history <- function(history) {
    any(vapply(history, function(entry) {
        is.list(entry) &&
        (identical(entry$type, ".openai_codex_output") ||
               isTRUE(entry$.openai_codex_output) ||
               identical(entry$type, "function_call_output"))
    }, logical(1)))
}

#' Check whether an agent request uses Responses
#'
#' Reports the routing decision used by \code{\link{agent}} without a
#' request or credential lookup. Hosts can use it before offering tools that
#' require a particular history format. This describes the wire, not the
#' model's availability or permission to use it.
#'
#' @param provider Provider name.
#' @param model Model identifier, or NULL for the provider default.
#' @param tools Tool schemas, as passed to \code{agent}.
#' @param web_search Search setting, as passed to \code{agent}.
#' @param history Conversation history, as passed to \code{agent}.
#' @return Logical scalar. TRUE for the Codex provider, or for OpenAI when
#'   search, GPT-6 tools, or an existing Responses history selects Responses.
#' @examples
#' agent_uses_responses("openai", "gpt-6-astra", tools = list(list(name = "lookup")))
#' agent_uses_responses("openai", "gpt-5.5", web_search = FALSE)
#' @export
agent_uses_responses <- function(provider, model = NULL, tools = list(),
                                 web_search = FALSE, history = NULL) {
    identical(provider, "openai_codex") ||
        (identical(provider, "openai") &&
         (!isFALSE(web_search) ||
          (length(tools) > 0L && .openai_requires_responses_tools(model)) ||
          .openai_responses_history(history)))
}

# Build a Responses API body for the standard OpenAI endpoint. Mirrors the
# Codex body but: keeps `max_output_tokens` (the public endpoint honors output
# caps, unlike /codex/responses), and omits Codex-only knobs (text.verbosity,
# the llm.api originator). `store = FALSE` + encrypted reasoning content match
# the Codex approach so reasoning items replay cleanly across agent turns.
.openai_responses_body <- function(messages, tools, system, model, ...) {
    extra <- list(...)
    if (is.null(system)) {
        extracted <- .openai_codex_extract_system(messages)
        system <- extracted$system %||% "You are a helpful assistant."
        messages <- extracted$messages
    }

    ws_tool <- .openai_codex_web_search_tool(extra$web_search)
    extra$web_search <- NULL

    cap <- extra$max_output_tokens %||% extra$max_completion_tokens %||% extra$max_tokens
    extra$max_tokens <- NULL
    extra$max_completion_tokens <- NULL
    extra$max_output_tokens <- NULL

    reasoning <- NULL
    if (!is.null(extra$reasoning_effort)) {
        reasoning <- list(effort = extra$reasoning_effort, summary = "auto")
        extra$reasoning_effort <- NULL
    }

    body <- list(model = model, instructions = system,
                 input = .openai_codex_messages_to_input(messages),
                 stream = TRUE, reasoning = reasoning,
                 include = list("reasoning.encrypted_content"), store = FALSE)
    if (!is.null(cap)) {
        body$max_output_tokens <- cap
    }

    all_tools <- c(tools, if (!is.null(ws_tool)) list(ws_tool))
    if (length(all_tools) > 0L) {
        body$tools <- all_tools
        body$tool_choice <- "auto"
        body$parallel_tool_calls <- TRUE
    }
    for (name in names(extra)) {
        body[[name]] <- extra[[name]]
    }
    body$stream <- TRUE
    body
}

.openai_responses_request <- function(messages, tools, system, model, config,
                                      on_delta = NULL, ...) {
    url <- paste0(config$base_url, "/v1/responses")
    headers <- c("Content-Type" = "application/json",
                 "accept" = "text/event-stream")
    if (!is.null(config$api_key) && nzchar(config$api_key)) {
        headers["Authorization"] <- paste("Bearer", config$api_key)
    }
    body <- .openai_responses_body(messages, tools, system, model, ...)
    .openai_codex_post_sse(url, body, headers, on_delta = on_delta)
}

.chat_openai_responses <- function(body, config, stream) {
    extracted <- .openai_codex_extract_system(body$messages)
    extra <- body
    extra$model <- NULL
    extra$messages <- NULL
    extra$stream <- NULL
    resp <- do.call(
                    .openai_responses_request,
                    c(list(messages = extracted$messages, tools = list(),
                           system = extracted$system, model = body$model, config = config), extra)
    )
    parsed <- .openai_codex_parse_response(resp)
    if (isTRUE(stream) && nzchar(parsed$text)) {
        cat(parsed$text, "\n", sep = "")
    }
    list(content = parsed$text, thinking = NULL,
         finish_reason = .openai_responses_finish_reason(parsed),
         usage = parsed$usage, citations = parsed$citations,
         searches = parsed$searches)
}

.agent_openai_responses <- function(messages, tools, system, model, config,
                                    on_delta = NULL, ...) {
    extra <- list(...)
    resp <- do.call(
                    .openai_responses_request,
                    c(list(messages = messages, tools = tools, system = system,
                           model = model, config = config, on_delta = on_delta), extra)
    )
    .openai_codex_parse_response(resp)
}
