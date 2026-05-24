# Agentic chat with tool use

#' Chat with tool use (agentic mode)
#'
#' Send a prompt to an LLM with tools. Automatically handles tool calls
#' in a loop until the model responds with text only.
#'
#' @param prompt Character. The user message.
#' @param tools List. Tool definitions (from mcp_tools_for_claude or manual).
#' @param tool_handler Function. Called with (name, args), returns result string.
#' @param system Character. System prompt.
#' @param model Character. Model name.
#' @param provider Character. Provider: "anthropic", "openai", "moonshot",
#'   or "ollama".
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
#' @param ... Additional parameters passed to the API.
#'
#' @return List with final response and conversation history. The
#'   returned \code{$usage} carries cumulative \code{input_tokens},
#'   \code{output_tokens}, \code{total_tokens}, and \code{cost} (USD
#'   scalar, derived from the bundled price snapshot; \code{0} for
#'   Ollama; \code{NA_real_} for models not in the snapshot).
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
                  provider = c("anthropic", "openai", "moonshot", "ollama"),
                  max_turns = 20L, verbose = TRUE, history = NULL,
                  history_callback = NULL, cache = c("none", "5m", "1h"),
                  thinking_budget_tokens = NULL, ...) {
    provider <- match.arg(provider)
    cache <- match.arg(cache)

    # Anthropic-only feature opt-ins emit a one-time warning when a
    # non-default value is passed against another provider so the
    # caller knows the request will be silently degraded.
    if (!identical(cache, "none") && !identical(provider, "anthropic")) {
        warning("`cache` is Anthropic-only; ignoring for provider \"",
                provider, "\".", call. = FALSE)
        cache <- "none"
    }
    if (!is.null(thinking_budget_tokens)) {
        # max_tokens flows in via ...; pull it out for validation.
        extra_validate <- list(...)
        .validate_thinking_budget(thinking_budget_tokens,
                                  max_tokens = extra_validate$max_tokens)
        if (!identical(provider, "anthropic")) {
            warning("`thinking_budget_tokens` is Anthropic-only; ignoring ",
                    "for provider \"", provider, "\".", call. = FALSE)
            thinking_budget_tokens <- NULL
        }
    }

    if (is.null(tool_handler) && length(tools) > 0) {
        stop("tool_handler required when tools are provided", call. = FALSE)
    }

    config <- .get_provider_config(provider)

    # Default models with tool support
    if (is.null(model)) {
        model <- switch(provider, anthropic = "claude-sonnet-4-6",
                        openai = "gpt-5.4-mini", moonshot = "kimi-k2.5",
                        ollama = "qwen3.5:9b")
    }

    # Convert tools to provider format
    provider_tools <- .convert_tools(tools, provider)

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

    while (turn < max_turns) {
        turn <- turn + 1L

        # Make API request with tools
        response <- switch(provider,
                           anthropic = .agent_anthropic(messages, provider_tools, system, model, config,
                cache = cache,
                thinking_budget_tokens = thinking_budget_tokens, ...),
                           openai = .agent_openai(messages, provider_tools, system, model, config, ...),
                           moonshot = .agent_openai(messages, provider_tools, system, model, config, ...),
                           ollama = .agent_ollama(messages, provider_tools, system, model, config, ...)
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
                    )
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
        for (tc in response$tool_calls) {
            if (verbose) {
                cat(sprintf("\n[Tool: %s]\n", tc$name))
                if (length(tc$arguments) > 0) {
                    cat(sprintf("  Args: %s\n",
                                jsonlite::toJSON(tc$arguments, auto_unbox = TRUE)))
                }
            }

            # Call tool handler
            result <- tryCatch(
                               tool_handler(tc$name, tc$arguments),
                               error = function(e) paste("Error:", e$message)
            )

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
                provider
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
        )
    )
}

# Convert tools to provider-specific format
.convert_tools <- function(tools, provider) {
    if (length(tools) == 0) {
        return(list())
    }

    switch(provider,
           anthropic = tools, # Already in Claude format

           openai =,
           moonshot = lapply(tools, function(t) {
        list(
             type = "function",
             `function` = list(name = t$name,
                               description = t$description %||% "",
                               parameters = t$input_schema)
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

    body <- list(model = model, messages = messages, max_tokens = 4096)

    if (!is.null(system)) {
        body$system <- .anthropic_system_with_cache(system, cache)
    }
    if (length(tools) > 0) {
        body$tools <- tools
    }
    if (!is.null(thinking_budget_tokens)) {
        body$thinking <- list(type = "enabled",
                              budget_tokens = as.integer(thinking_budget_tokens))
    }

    extra <- list(...)
    for (name in names(extra)) {
        body[[name]] <- extra[[name]]
    }

    headers <- c("Content-Type" = "application/json",
                 "x-api-key" = config$api_key,
                 "anthropic-version" = "2023-06-01")

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

    list(
         text = paste(text_parts, collapse = "\n"),
         tool_calls = tool_calls,
         assistant_message = list(role = "assistant", content = resp$content),
         usage = resp$usage # input_tokens, output_tokens
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
    api_messages <- c(api_messages, messages)

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

    headers <- c("Content-Type" = "application/json",
                 "Authorization" = paste("Bearer", config$api_key))

    resp <- .post_json(url, body, headers)

    # Parse response
    choice <- resp$choices[[1]]
    msg <- choice$message

    tool_calls <- list()
    if (!is.null(msg$tool_calls)) {
        for (tc in msg$tool_calls) {
            args <- tryCatch(
                             jsonlite::fromJSON(tc$`function`$arguments, simplifyVector = FALSE),
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
    api_messages <- c(api_messages, messages)

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
#' @param provider Character. Provider: "anthropic", "openai", "moonshot",
#'   or "ollama".
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
                         provider = c("anthropic", "openai", "moonshot", "ollama"),
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

