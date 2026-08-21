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
# the standard `openai` provider only routes here when web_search is on;
# otherwise it stays on chat-completions (no behaviour change).

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

    cap <- extra$max_output_tokens %||% extra$max_tokens
    extra$max_tokens <- NULL
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
    list(content = parsed$text, thinking = NULL, finish_reason = NULL,
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
