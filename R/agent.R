# Agentic chat with tool use

#' Chat with tool use (agentic mode)
#'
#' Send a prompt to an LLM with tools. Automatically handles tool calls
#' in a loop until the model responds with text only.
#'
#' @param prompt Character. The user message.
#' @param tools List. Tool definitions (from mcp_tools_for_claude or manual).
#' @param tool_handler Function. Called with `(name, args)` and returns a
#'   result string. If it declares a formal named `context`, it also
#'   receives (by name) a read-only per-call snapshot with `assistant_text` (the model's
#'   text for this turn), `agent_turn`, `call_index`, `call_count`, and
#'   `provider`; two-argument handlers are called unchanged.
#' @param system Character. System prompt.
#' @param model Character. Model name.
#' @param provider Character. Provider: "anthropic", "anthropic_claude", "openai", "moonshot",
#'   "openai_codex", "ollama", or "openai_compatible" (a generic
#'   OpenAI-compatible gateway; requires a base URL via
#'   \code{llm_base()} or \code{OPENAI_COMPATIBLE_BASE_URL}, and an
#'   explicit \code{model}).
#' @param max_turns Integer. Maximum tool-use turns (default: 20).
#' @param verbose Logical. Print tool calls and results.
#' @param history List or NULL. Previous conversation history to continue from.
#' @param history_callback Function or NULL. Called as
#'   \code{history_callback(history)} after each assistant message is
#'   appended and after each tool result is appended. Lets callers
#'   snapshot intermediate state so an interrupt mid-turn doesn't lose
#'   the work that was already done. Errors raised inside the callback
#'   are swallowed so telemetry/snapshotting can't break a turn.
#' @param cache Character. Anthropic prompt caching for the system
#'   message: \code{"none"} (default), \code{"5m"}, or \code{"1h"}
#'   ephemeral TTL. Anthropic-only; warns and degrades to \code{"none"}
#'   for other providers.
#' @param thinking_budget_tokens Integer or NULL. Anthropic extended
#'   thinking budget; must be at least 1024 and less than
#'   \code{max_tokens}. Anthropic-only; ignored with a warning for
#'   other providers.
#' @param web_search Enable provider-native (server-side) web search:
#'   \code{FALSE} (default), \code{TRUE}, or a list of options
#'   (\code{allowed_domains}, \code{user_location}). Server-side, so it is
#'   not gated by \code{tool_handler}; the result accumulates
#'   \code{citations} and \code{searches} across turns. Wired for
#'   \code{"openai_codex"} and \code{"openai"} (OpenAI Responses
#'   \code{web_search} tool; for \code{"openai"} the run is routed through
#'   the Responses endpoint), \code{"anthropic"},
#'   \code{"anthropic_claude"}, and \code{"moonshot"}
#'   (the \code{$web_search} builtin, whose calls are handled internally
#'   rather than via \code{tool_handler}); ignored with a warning
#'   otherwise.
#' @param on_delta Function or NULL. Called with each fragment of the
#'   model's text as it arrives, before the response is complete, so a
#'   caller can start displaying or speaking it. Called many times per
#'   turn, with a single non-empty character scalar each time; its
#'   return value is ignored.
#'
#'   Calling \code{\link{llm_cancel}} from inside it abandons the
#'   request: the connection closes, the provider stops generating, and
#'   \code{agent()} returns immediately with \code{cancelled = TRUE} and
#'   whatever text had arrived. The assistant message is not appended to
#'   \code{history} in that case, because a partial one can carry an
#'   unmatched tool call that breaks the following request; the caller
#'   knows what was delivered and records it.
#'
#'   Wired for the Responses wire only -- \code{"openai_codex"}, and
#'   \code{"openai"} when \code{web_search} routes it there. Every other
#'   provider posts once and waits, so there is nothing to stream;
#'   passing it warns and is ignored rather than silently doing nothing.
#' @param ... Additional parameters passed to the API.
#'
#' @return List with final response and conversation history. The
#'   returned \code{$usage} carries cumulative \code{input_tokens},
#'   \code{output_tokens}, \code{total_tokens}, and \code{cost} (USD
#'   scalar, derived from the bundled price snapshot; \code{0} for
#'   Ollama; \code{NA_real_} for models not in the snapshot). It also
#'   carries cumulative cache activity: \code{cache_read_input_tokens}
#'   (Anthropic cache reads plus OpenAI/Moonshot cached prompt tokens),
#'   \code{cache_creation_input_tokens} (total Anthropic cache writes),
#'   and the per-TTL split \code{cache_creation$ephemeral_5m_input_tokens}
#'   / \code{cache_creation$ephemeral_1h_input_tokens}. Passing this
#'   \code{$usage} back to \code{\link{usage_cost}} recomputes the same
#'   \code{cost}.
#' @export
#'
#' @examples
#' \dontrun{
#' # With MCP server
#' conn <- mcp_connect("r", "mcp_server.R")
#' tools <- mcp_tools_for_claude(conn)
#'
#' result <- agent(
#'   "What files are in the current directory?",
#'   tools = tools,
#'   tool_handler = function(name, args) {
#'     mcp_call(conn, name, args)$text
#'   }
#' )
#' }
agent <- function(prompt, tools = list(), tool_handler = NULL, system = NULL,
                  model = NULL,
                  provider = c("anthropic", "anthropic_claude", "openai", "moonshot",
                               "openai_codex", "ollama", "openai_compatible"),
                  max_turns = 20L, verbose = TRUE, history = NULL,
                  history_callback = NULL, cache = c("none", "5m", "1h"),
                  thinking_budget_tokens = NULL, web_search = FALSE,
                  on_delta = NULL, ...) {
    provider <- match.arg(provider)
    cache <- match.arg(cache)

    # Anthropic-only feature opt-ins emit a one-time warning when a
    # non-default value is passed against another provider so the
    # caller knows the request will be silently degraded.
    if (!identical(cache, "none") && !.is_anthropic(provider)) {
        warning("`cache` is Anthropic-only; ignoring for provider \"",
                provider, "\".", call. = FALSE)
        cache <- "none"
    }
    if (!is.null(thinking_budget_tokens)) {
        # max_tokens flows in via ...; pull it out for validation.
        extra_validate <- list(...)
        .validate_thinking_budget(thinking_budget_tokens,
                                  max_tokens = extra_validate$max_tokens)
        if (!.is_anthropic(provider)) {
            warning("`thinking_budget_tokens` is Anthropic-only; ignoring ",
                    "for provider \"", provider, "\".", call. = FALSE)
            thinking_budget_tokens <- NULL
        }
    }
    # on_delta only works where the request is streamed, and today that
    # is the Responses wire alone -- every other provider posts once and
    # waits. Warned rather than ignored, on `cache`'s reasoning: a caller
    # that passed a callback is building on it, and silence would have it
    # believe the deltas were arriving and the model simply had nothing
    # to say until the end.
    if (!is.null(on_delta)) {
        if (!is.function(on_delta)) {
            stop("`on_delta` must be a function of one argument.",
                 call. = FALSE)
        }
        if (!(identical(provider, "openai_codex") ||
                (identical(provider, "openai") && !isFALSE(web_search)))) {
            warning("`on_delta` is only wired for the Responses providers ",
                    "(\"openai_codex\", or \"openai\" with web_search); ",
                    "ignoring for provider \"", provider, "\".", call. = FALSE)
            on_delta <- NULL
        }
    }
    if (!isFALSE(web_search) && !provider %in% .web_search_providers()) {
        warning("`web_search` is not yet supported for provider \"", provider,
                "\"; ignoring.", call. = FALSE)
        web_search <- FALSE
    }

    if (is.null(tool_handler) && length(tools) > 0) {
        stop("tool_handler required when tools are provided", call. = FALSE)
    }

    config <- .get_provider_config(provider)
    .check_openai_compatible(config, model)

    # Default models with tool support
    if (is.null(model)) {
        model <- switch(provider, anthropic =,
                        anthropic_claude = "claude-sonnet-4-6",
                        openai = "gpt-5.4-mini", moonshot = "kimi-k2.5",
                        openai_codex = "gpt-5.5", ollama = "qwen3.5:9b")
    }

    # Server-side web search on the standard openai provider runs over the
    # Responses endpoint (the chat-completions path can't search the default
    # models). The whole run then uses the Responses wire shape -- flat tools,
    # function_call_output results -- which matches the openai_codex format, so
    # `wire` drives tool conversion / dispatch / result append while `provider`
    # stays "openai" for cost lookup and the returned object.
    use_responses <- identical(provider, "openai") && !isFALSE(web_search)
    if (use_responses) {
        wire <- "openai_codex"
    } else if (identical(provider, "anthropic_claude")) {
        # Subscription OAuth shares the Messages API wire shape with the
        # API-key anthropic provider (only the auth header differs), so the
        # anthropic wire drives tool conversion, dispatch, and tool-result
        # appending. Without this, .append_tool_result() / .convert_tools()
        # don't match the literal "anthropic_claude" and the messages array
        # gets corrupted on the turn after a tool call (a 400 from the API).
        wire <- "anthropic"
    } else if (identical(provider, "openai_compatible")) {
        # Generic gateways speak the OpenAI chat-completions wire shape,
        # so the openai wire drives tool conversion / dispatch / result
        # appending while `provider` stays "openai_compatible" for cost
        # lookup and the returned object.
        wire <- "openai"
    } else {
        wire <- provider
    }

    # Convert tools to provider format
    provider_tools <- .convert_tools(tools, wire)

    # Moonshot web search is a `$web_search` builtin tool the model calls and we
    # echo back (see R/moonshot.R); add it alongside any user tools. The agent
    # loop intercepts those calls instead of routing them to tool_handler.
    moonshot_search <- identical(provider, "moonshot") && !isFALSE(web_search)
    if (moonshot_search) {
        provider_tools <- c(provider_tools,
                            list(.moonshot_web_search_tool(web_search)))
    }

    # Build initial messages (prepend history if provided)
    if (!is.null(history)) {
        messages <- history
    } else {
        messages <- list()
    }
    messages[[length(messages) + 1]] <- list(role = "user", content = prompt)

    turn <- 0L

    # Track cumulative token usage and cost. Cost is summed per turn:
    # cache token classes are per-response, so pricing each turn and
    # adding is correct and lets a single unpriceable turn propagate to
    # an NA total.
    total_input_tokens <- 0L
    total_output_tokens <- 0L
    total_cache_read <- 0L
    total_cache_write_5m <- 0L
    total_cache_write_1h <- 0L
    total_cost <- 0
    cost_na <- FALSE
    # Provider-native web search activity, accumulated across turns.
    total_citations <- list()
    total_searches <- list()

    # Context-aware handlers: when the caller's tool_handler declares a
    # `context` formal, pass it (by name) a read-only per-call snapshot
    # (model text, turn/call indices, provider). 2-arg handlers unchanged.
    handler_wants_context <- is.function(tool_handler) &&
    "context" %in% names(formals(tool_handler))

    while (turn < max_turns) {
        turn <- turn + 1L

        # Make API request with tools
        response <- if (use_responses) {
            .agent_openai_responses(messages, provider_tools, system, model,
                                    config, web_search = web_search,
                                    on_delta = on_delta, ...)
        } else switch(provider,
                      anthropic =,
                      anthropic_claude = .agent_anthropic(messages, provider_tools, system, model, config,
                cache = cache,
                thinking_budget_tokens = thinking_budget_tokens,
                web_search = web_search, ...),
                      openai = .agent_openai(messages, provider_tools, system, model,
                config, ...),
                      moonshot = .agent_openai(messages, provider_tools, system,
                model, config, ...),
                      openai_compatible = .agent_openai(messages, provider_tools,
                system, model, config, ...),
                      openai_codex = .agent_openai_codex(messages, provider_tools,
                system, model, config, web_search = web_search,
                on_delta = on_delta, ...),
                      ollama = .agent_ollama(messages, provider_tools, system, model,
                config, ...)
        )

        # Accumulate token usage and per-turn cost. Uses `[[` exact
        # matching throughout: `$` would partial-match (e.g.
        # prompt_tokens -> prompt_tokens_details).
        if (!is.null(response$usage)) {
            u <- response$usage
            # Anthropic format
            if (!is.null(u[["input_tokens"]])) {
                total_input_tokens <- total_input_tokens + u[["input_tokens"]]
                total_output_tokens <- total_output_tokens + u[["output_tokens"]]
            }
            # OpenAI/Ollama format
            if (!is.null(u[["prompt_tokens"]])) {
                total_input_tokens <- total_input_tokens + u[["prompt_tokens"]]
                total_output_tokens <- total_output_tokens + u[["completion_tokens"]]
            }
            # Cache token classes via the shared extractor so the
            # per-TTL Anthropic write split is captured (not just the
            # flat total); cache_read covers Anthropic reads, and
            # .openai_cached_tokens adds OpenAI cached prompt tokens.
            ct <- .cache_tokens(u)
            total_cache_read <- total_cache_read + ct$read +
            .openai_cached_tokens(u)
            total_cache_write_5m <- total_cache_write_5m + ct$write_5m
            total_cache_write_1h <- total_cache_write_1h + ct$write_1h
            turn_cost <- usage_cost(model, provider, u)
            if (is.na(turn_cost)) {
                cost_na <- TRUE
            } else {
                total_cost <- total_cost + turn_cost
            }
        }
        total_citations <- c(total_citations, response$citations %||% list())
        total_searches <- c(total_searches, response$searches %||% list())

        # Cancelled from inside on_delta. Returns before the tool-call
        # check, because a cancelled response can carry a half-built
        # tool call and running it would execute something the model
        # had not finished asking for.
        #
        # The assistant message is deliberately NOT appended. A partial
        # one is the thing most likely to be malformed -- an unmatched
        # tool_use block makes the *next* request fail, which is a long
        # way from here -- and the caller knows better than this loop
        # what was actually delivered. It gets the text and decides.
        if (isTRUE(response$cancelled)) {
            return(list(
                        content = response$text,
                        cancelled = TRUE,
                        model = model,
                        provider = provider,
                        turns = turn,
                        history = messages,
                        usage = list(
                                     input_tokens = total_input_tokens,
                                     output_tokens = total_output_tokens,
                                     total_tokens = total_input_tokens +
                                     total_output_tokens,
                                     cache_read_input_tokens = total_cache_read,
                                     cache_creation_input_tokens =
                                     total_cache_write_5m + total_cache_write_1h,
                                     cache_creation = list(
                            ephemeral_5m_input_tokens = total_cache_write_5m,
                            ephemeral_1h_input_tokens = total_cache_write_1h),
                                     cost = if (cost_na) NA_real_ else total_cost
                    ),
                        citations = total_citations,
                        searches = total_searches
                ))
        }

        # Check if done (no tool calls)
        if (length(response$tool_calls) == 0) {
            # Append final assistant message so caller's history is complete
            messages[[length(messages) + 1]] <- response$assistant_message
            .fire_history_callback(history_callback, messages)
            return(list(
                        content = response$text,
                        model = model,
                        provider = provider,
                        turns = turn,
                        history = messages,
                        usage = list(
                                     input_tokens = total_input_tokens,
                                     output_tokens = total_output_tokens,
                                     total_tokens = total_input_tokens + total_output_tokens,
                                     cache_read_input_tokens = total_cache_read,
                                     cache_creation_input_tokens = total_cache_write_5m + total_cache_write_1h,
                                     cache_creation = list(
                            ephemeral_5m_input_tokens = total_cache_write_5m,
                            ephemeral_1h_input_tokens = total_cache_write_1h),
                                     cost = if (cost_na) NA_real_ else total_cost
                    ),
                        citations = total_citations,
                        searches = total_searches
                ))
        }

        # Add assistant message (carries the tool_use blocks for this round)
        messages[[length(messages) + 1]] <- response$assistant_message
        .fire_history_callback(history_callback, messages)

        # Process tool calls one at a time and append each result to
        # history as it's produced, firing the callback after each.
        # This means an interrupt mid-batch leaves the completed tools'
        # results in the snapshot the callback received, so the caller
        # can preserve them instead of losing the whole batch.
        #
        # call_index / call_count in the handler context count over calls
        # actually dispatched to tool_handler, excluding ones consumed
        # internally (Moonshot's server-side $web_search echo), so a
        # context-aware handler can reliably detect the last call in a batch.
        is_dispatched <- vapply(response$tool_calls, function(tc) {
            !(moonshot_search && .is_moonshot_web_search(tc))
        }, logical(1))
        dispatch_count <- sum(is_dispatched)
        dispatch_index <- 0L

        for (i in seq_along(response$tool_calls)) {
            tc <- response$tool_calls[[i]]
            if (verbose) {
                cat(sprintf("\n[Tool: %s]\n", tc$name))
                if (length(tc$arguments) > 0) {
                    cat(sprintf("  Args: %s\n",
                                jsonlite::toJSON(tc$arguments, auto_unbox = TRUE)))
                }
            }

            # Moonshot's $web_search builtin is handled server-side: echo the
            # call's arguments straight back (the search_id inside is what the
            # backend keys on) and record the search, rather than dispatching to
            # the caller's tool_handler.
            if (moonshot_search && .is_moonshot_web_search(tc)) {
                result <- .moonshot_web_search_echo(tc$arguments)
                total_searches <- c(total_searches,
                                    list(list(query = NA_character_, status = "completed")))
            } else {
                dispatch_index <- dispatch_index + 1L
                if (handler_wants_context) {
                    # Read-only per-call snapshot. Passed by name so a handler
                    # that declares `context` after `...` still receives it.
                    ctx <- list(assistant_text = response$text %||% "",
                                agent_turn = turn,
                                call_index = dispatch_index,
                                call_count = dispatch_count,
                                provider = provider)
                    result <- tryCatch(
                                       tool_handler(tc$name, tc$arguments, context = ctx),
                                       error = function(e) paste("Error:", e$message)
                    )
                } else {
                    result <- tryCatch(
                                       tool_handler(tc$name, tc$arguments),
                                       error = function(e) paste("Error:", e$message)
                    )
                }
            }

            if (verbose) {
                display <- if (nchar(result) > 500) {
                    paste0(substr(result, 1, 500), "...")
                } else {
                    result
                }
                cat(sprintf("  Result: %s\n", display))
            }

            messages <- .append_tool_result(
                messages,
                list(id = tc$id, name = tc$name, result = result),
                wire
            )
            .fire_history_callback(history_callback, messages)
        }
    }

    warning("Reached max_turns (", max_turns, ")")
    list(
         content = "[Max turns reached]",
         model = model,
         provider = provider,
         turns = turn,
         history = messages,
         usage = list(
                      input_tokens = total_input_tokens,
                      output_tokens = total_output_tokens,
                      total_tokens = total_input_tokens + total_output_tokens,
                      cache_read_input_tokens = total_cache_read,
                      cache_creation_input_tokens = total_cache_write_5m + total_cache_write_1h,
                      cache_creation = list(
                ephemeral_5m_input_tokens = total_cache_write_5m,
                ephemeral_1h_input_tokens = total_cache_write_1h),
                      cost = if (cost_na) NA_real_ else total_cost
        ),
         citations = total_citations,
         searches = total_searches
    )
}

# Convert tools to provider-specific format
.convert_tools <- function(tools, provider) {
    if (length(tools) == 0) {
        return(list())
    }

    switch(provider,
           anthropic =,
           anthropic_claude = tools, # Already in Claude format

           openai =,
           moonshot = lapply(tools, function(t) {
        list(
             type = "function",
             `function` = list(name = t$name,
                               description = t$description %||% "",
                               parameters = t$input_schema)
        )
    }),

           openai_codex = lapply(tools, function(t) {
        list(
             type = "function",
             name = t$name,
             description = t$description %||% "",
             parameters = t$input_schema
        )
    }),

           ollama = lapply(tools, function(t) {
        list(
             type = "function",
             `function` = list(
                               name = t$name,
                               description = t$description %||% "",
                               parameters = t$input_schema
            )
        )
    })
    )
}

# Anthropic request
.agent_anthropic <- function(messages, tools, system, model, config,
                             cache = "none", thinking_budget_tokens = NULL,
                             ...) {
    url <- paste0(config$base_url, config$chat_path)

    body <- list(model = model, messages = .llm_blocks(messages, "anthropic"),
                 max_tokens = 4096)

    sys <- .anthropic_system(system, cache,
                             oauth = is.function(config$credentials))
    if (!is.null(sys)) {
        body$system <- sys
    }
    if (length(tools) > 0) {
        body$tools <- tools
    }
    if (!is.null(thinking_budget_tokens)) {
        body$thinking <- list(type = "enabled",
                              budget_tokens = as.integer(thinking_budget_tokens))
    }

    extra <- list(...)
    ws_tool <- .anthropic_web_search_tool(extra$web_search)
    extra$web_search <- NULL
    if (!is.null(ws_tool)) {
        body$tools <- c(body$tools, list(ws_tool))
    }
    for (name in names(extra)) {
        body[[name]] <- extra[[name]]
    }

    headers <- .anthropic_headers(config)

    resp <- .post_json(url, body, headers)

    # Parse response
    text_parts <- character()
    tool_calls <- list()

    for (block in resp$content) {
        if (block$type == "text") {
            text_parts <- c(text_parts, block$text)
        } else if (block$type == "tool_use") {
            tool_calls[[length(tool_calls) + 1]] <- list(
                id = block$id,
                name = block$name,
                arguments = block$input
            )
        }
    }

    search_info <- .anthropic_search_blocks(resp$content)

    list(
         text = paste(text_parts, collapse = "\n"),
         tool_calls = tool_calls,
         assistant_message = list(role = "assistant", content = resp$content),
         usage = resp$usage, # input_tokens, output_tokens
         citations = search_info$citations,
         searches = search_info$searches
    )
}

# OpenAI request
.agent_openai <- function(messages, tools, system, model, config, ...) {
    url <- paste0(config$base_url, config$chat_path)

    # Build messages with system
    api_messages <- list()
    if (!is.null(system)) {
        api_messages[[1]] <- list(role = "system", content = system)
    }
    api_messages <- c(api_messages, .llm_blocks(messages, "openai"))

    body <- list(model = model, messages = api_messages)

    if (length(tools) > 0) {
        body$tools <- tools
    }

    extra <- list(...)
    # OpenAI deprecated max_tokens in favor of max_completion_tokens
    # and reasoning (o-series) models reject max_tokens entirely. Map
    # for the OpenAI endpoint only; Moonshot, which shares this
    # helper, still expects max_tokens.
    if (identical(config$provider, "openai") &&
        !is.null(extra$max_tokens) &&
        is.null(extra$max_completion_tokens)) {
        extra$max_completion_tokens <- extra$max_tokens
        extra$max_tokens <- NULL
    }
    for (name in names(extra)) {
        body[[name]] <- extra[[name]]
    }

    # Match .chat_openai_compatible: skip the Authorization header when
    # there is no key, so keyless gateways (openai_compatible behind a
    # corporate proxy) don't receive a bare "Bearer " header.
    headers <- c("Content-Type" = "application/json")
    if (!is.null(config$api_key) && nzchar(config$api_key)) {
        headers["Authorization"] <- paste("Bearer", config$api_key)
    }

    resp <- .post_json(url, body, headers)

    # Parse response
    choice <- resp$choices[[1]]
    msg <- choice$message

    tool_calls <- list()
    if (!is.null(msg$tool_calls)) {
        for (tc in msg$tool_calls) {
            args <- tryCatch(
                             jsonlite::fromJSON(tc$`function`$arguments,
                    simplifyVector = FALSE),
                             error = function(e) list()
            )
            tool_calls[[length(tool_calls) + 1]] <- list(
                id = tc$id,
                name = tc$`function`$name,
                arguments = args
            )
        }
    }

    list(
         text = msg$content %||% "",
         tool_calls = tool_calls,
         assistant_message = msg,
         usage = resp$usage # prompt_tokens, completion_tokens, total_tokens
    )
}

# Ollama request (OpenAI-compatible)
.agent_ollama <- function(messages, tools, system, model, config, ...) {
    url <- paste0(config$base_url, config$chat_path)

    api_messages <- list()
    if (!is.null(system)) {
        api_messages[[1]] <- list(role = "system", content = system)
    }
    api_messages <- c(api_messages, .llm_blocks(messages, "openai"))

    body <- list(model = model, messages = api_messages, stream = FALSE)

    if (length(tools) > 0) {
        body$tools <- tools
    }

    extra <- list(...)
    for (name in names(extra)) {
        body[[name]] <- extra[[name]]
    }

    headers <- c("Content-Type" = "application/json")

    resp <- .post_json(url, body, headers)

    # Parse response (OpenAI-compatible format: choices[].message)
    msg <- resp$choices[[1]]$message

    tool_calls <- list()
    if (!is.null(msg$tool_calls)) {
        for (i in seq_along(msg$tool_calls)) {
            tc <- msg$tool_calls[[i]]
            # Parse arguments from JSON string (same as OpenAI)
            args <- tryCatch(
                             jsonlite::fromJSON(tc$`function`$arguments,
                    simplifyVector = FALSE),
                             error = function(e) list()
            )
            # Ollama sometimes omits tc$id; synthesize one and write it back
            # into the assistant message so the corresponding role="tool"
            # result message can reference the same id. Without this the
            # canonical tool_calls list and the on-the-wire history disagree
            # on the call id, which breaks history walks.
            synthesized_id <- tc$id %||% paste0("call_", sample(1e9, 1))
            msg$tool_calls[[i]]$id <- synthesized_id
            tool_calls[[length(tool_calls) + 1]] <- list(
                id = synthesized_id,
                name = tc$`function`$name,
                arguments = args
            )
        }
    }

    list(
         text = msg$content %||% "",
         tool_calls = tool_calls,
         assistant_message = msg,
         usage = resp$usage
    )
}

# Add tool results to message history
.add_tool_results <- function(messages, results, provider) {
    # Backwards-compatible batch wrapper. New code paths should call
    # .append_tool_result directly so the history_callback in agent()
    # can fire between each append.
    for (r in results) {
        messages <- .append_tool_result(messages, r, provider)
    }
    messages
}

# Append a single tool result to history in the provider's expected
# shape. For Anthropic, multiple tool_results for one assistant turn
# share a single trailing user message (extended in place); for the
# OpenAI-family providers each tool result is its own role="tool"
# message.
.append_tool_result <- function(messages, result, provider) {
    switch(provider,
           anthropic = {
        block <- list(type = "tool_result", tool_use_id = result$id,
                      content = result$result)
        last <- length(messages)
        if (last >= 1L &&
            identical(messages[[last]]$role, "user") &&
            is.list(messages[[last]]$content) &&
            length(messages[[last]]$content) > 0L &&
            identical(messages[[last]]$content[[1]]$type, "tool_result")) {
            # Extend the existing batch user message.
            messages[[last]]$content <- c(messages[[last]]$content, list(block))
        } else {
            messages[[length(messages) + 1L]] <- list(role = "user",
                content = list(block))
        }
        messages
    },
           openai =,
           moonshot =,
           ollama = {
        messages[[length(messages) + 1L]] <- list(
            role = "tool",
            tool_call_id = result$id,
            name = result$name,
            content = result$result
        )
        messages
    },
           openai_codex = {
        messages[[length(messages) + 1L]] <- list(
            type = "function_call_output",
            call_id = result$id,
            output = result$result
        )
        messages
    }
    )
}

# Invoke the user-supplied history callback if any, swallowing errors.
# Callers should pass the current full messages list; the callback
# typically uses it to snapshot intermediate state so an interrupt
# mid-turn doesn't lose completed tool calls.
.fire_history_callback <- function(callback, messages) {
    if (is.null(callback)) {
        return(invisible(NULL))
    }
    tryCatch(callback(messages), error = function(e) NULL)
    invisible(NULL)
}

# Helper: POST JSON request
.post_json <- function(url, body, headers) {
    .llm_assert_translated(body$messages, "the request body")
    h <- curl::new_handle()
    curl::handle_setopt(h,
                        customrequest = "POST",
                        postfields = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null")
    )
    curl::handle_setheaders(h, .list = as.list(headers))

    resp <- curl::curl_fetch_memory(url, handle = h)

    if (resp$status_code >= 400) {
        err <- tryCatch(
                        jsonlite::fromJSON(rawToChar(resp$content)),
                        error = function(e) list(error = list(message = rawToChar(resp$content)))
        )
        stop("API error (", resp$status_code, "): ",
             err$error$message %||% "Unknown error", call. = FALSE)
    }

    jsonlite::fromJSON(rawToChar(resp$content), simplifyVector = FALSE)
}

#' Create an agent with MCP servers
#'
#' Convenience function that sets up MCP connections and returns
#' a function for chatting with tools.
#'
#' @param servers Named list of server configs. Each can be:
#'   - `list(port = 7850)` for already-running servers
#'   - `list(command = "r", args = "server.R", port = 7850)` to start and connect
#' @param system Character. Default system prompt.
#' @param model Character. Default model.
#' @param provider Character. Provider: "anthropic", "anthropic_claude", "openai", "moonshot",
#'   "openai_codex", "ollama", or "openai_compatible".
#' @param verbose Logical. Print tool calls.
#'
#' @return A function that takes a prompt and returns a response.
#' @export
#'
#' @examples
#' \dontrun{
#' # Connect to already-running server
#' chat_fn <- create_agent(
#'   servers = list(codeR = list(port = 7850)),
#'   system = "You are a helpful coding assistant."
#' )
#'
#' # Or start server automatically
#' chat_fn <- create_agent(
#'   servers = list(
#'     codeR = list(command = "r", args = "mcp_server.R", port = 7850)
#'   )
#' )
#'
#' result <- chat_fn("List files in current directory")
#' }
create_agent <- function(servers = list(), system = NULL, model = NULL,
                         provider = c("anthropic", "anthropic_claude", "openai", "moonshot",
                                      "openai_codex", "ollama", "openai_compatible"),
                         verbose = TRUE) {
    provider <- match.arg(provider)

    # Connect to all servers
    connections <- list()
    for (name in names(servers)) {
        srv <- servers[[name]]

        if (!is.null(srv$command)) {
            # Start server and connect
            connections[[name]] <- mcp_start(command = srv$command,
                args = srv$args, port = srv$port, name = name)
        } else {
            # Connect to existing server
            connections[[name]] <- mcp_connect(
                host = srv$host %||% "localhost",
                port = srv$port,
                name = name
            )
        }
    }

    # Gather all tools (in Claude format - will be converted per-provider)
    all_tools <- list()
    tool_map <- list()

    for (name in names(connections)) {
        conn <- connections[[name]]
        for (tool in conn$tools) {
            all_tools[[length(all_tools) + 1]] <- list(
                name = tool$name,
                description = tool$description %||% "",
                input_schema = tool$inputSchema
            )
            tool_map[[tool$name]] <- conn
        }
    }

    # Create tool handler
    handler <- function(name, args) {
        conn <- tool_map[[name]]
        if (is.null(conn)) {
            return(paste("Unknown tool:", name))
        }
        mcp_call(conn, name, args)$text
    }

    # Return chat function
    function(prompt, ...) {
        agent(
              prompt = prompt,
              tools = all_tools,
              tool_handler = handler,
              system = system,
              model = model,
              provider = provider,
              verbose = verbose,
              ...
        )
    }
}
