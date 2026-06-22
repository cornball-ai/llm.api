# Core chat functionality

# Validate a thinking budget against Anthropic's documented
# constraints: it must be a positive integer of at least 1024 tokens,
# and (when max_tokens is set) it must leave room for the regular
# completion -- the budget is counted within max_tokens.
.validate_thinking_budget <- function(thinking_budget_tokens,
                                      max_tokens = NULL) {
    if (!is.numeric(thinking_budget_tokens) ||
        length(thinking_budget_tokens) != 1L ||
        is.na(thinking_budget_tokens) ||
        thinking_budget_tokens != as.integer(thinking_budget_tokens)) {
        stop("`thinking_budget_tokens` must be a single integer.",
             call. = FALSE)
    }
    if (thinking_budget_tokens < 1024L) {
        stop("`thinking_budget_tokens` must be at least 1024 ",
             "(Anthropic's documented minimum).", call. = FALSE)
    }
    if (!is.null(max_tokens) &&
        thinking_budget_tokens >= as.integer(max_tokens)) {
        stop("`thinking_budget_tokens` (", thinking_budget_tokens,
             ") must be strictly less than `max_tokens` (",
             max_tokens, "); the thinking budget counts against ",
             "max_tokens and must leave room for the completion.",
             call. = FALSE)
    }
    invisible(TRUE)
}

# Wrap the system message in a cache_control block when caching is
# requested, or pass it through as plain text when cache == "none".
# The "5m" and "1h" values map to Anthropic's ephemeral cache TTLs.
.anthropic_system_with_cache <- function(system_msg, cache) {
    if (identical(cache, "none")) {
        return(system_msg)
    }
    control <- if (identical(cache, "1h")) {
        list(type = "ephemeral", ttl = "1h")
    } else {
        list(type = "ephemeral")
    }
    list(list(type = "text", text = system_msg, cache_control = control))
}

# Providers with provider-native web search wired up. Grows as each provider's
# native mechanism is added (openai_codex/openai Responses tool, anthropic
# web_search_<date>, moonshot $web_search).
.web_search_providers <- function() {
    c("openai_codex", "openai", "anthropic", "moonshot")
}

# Anthropic server-side web search tool from the provider-neutral toggle, or
# NULL when off. Uses the basic web_search_20250305 variant: it works across all
# models (no model->version mapping) and returns clean per-text-block url
# citations, unlike the dynamic-filtering 20260209 variant (which also pulls in
# code execution). Supports the full option set.
.anthropic_web_search_tool <- function(ws) {
    if (is.null(ws) || isFALSE(ws)) {
        return(NULL)
    }
    tool <- list(type = "web_search_20250305", name = "web_search")
    if (is.list(ws)) {
        if (!is.null(ws$max_uses)) {
            tool$max_uses <- as.integer(ws$max_uses)
        }
        if (!is.null(ws$allowed_domains)) {
            tool$allowed_domains <- as.list(ws$allowed_domains)
        }
        if (!is.null(ws$blocked_domains)) {
            tool$blocked_domains <- as.list(ws$blocked_domains)
        }
        if (!is.null(ws$user_location)) {
            tool$user_location <- ws$user_location
        }
    }
    tool
}

# Extract web-search citations and search queries from a list of Anthropic
# content blocks (parsed with simplifyVector = FALSE). Citations live on text
# blocks; the search query lives on the server_tool_use block.
.anthropic_search_blocks <- function(content) {
    citations <- list()
    searches <- list()
    for (b in content %||% list()) {
        if (identical(b$type, "text")) {
            for (cit in b$citations %||% list()) {
                citations[[length(citations) + 1L]] <- list(url = cit$url,
                    title = cit$title)
            }
        } else if (identical(b$type, "server_tool_use") &&
            identical(b$name, "web_search")) {
            searches[[length(searches) + 1L]] <- list(
                query = b$input$query, status = "completed")
        }
    }
    list(citations = citations, searches = searches)
}

#' Chat with an LLM
#'
#' Send a message to a Large Language Model and get a response.
#'
#' @param prompt Character. The user message to send.
#' @param model Character. Model name (e.g., "gpt-5.4-mini", "claude-sonnet-4-6", "qwen3.5:9b").
#' @param system Character or NULL. System prompt to set context.
#' @param history List or NULL. Previous conversation turns.
#' @param temperature Numeric or NULL. Sampling temperature (0-2).
#' @param max_tokens Integer or NULL. Maximum tokens in response.
#' @param provider Character. Provider: "auto", "openai", "anthropic",
#'   "moonshot", "openai_codex", or "ollama".
#' @param stream Logical. Stream the response (prints as it arrives).
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
#'   (\code{allowed_domains}, \code{user_location}). The model searches
#'   on its own when useful; the result carries \code{citations} and
#'   \code{searches}. Wired for \code{"openai_codex"} and \code{"openai"}
#'   (OpenAI Responses \code{web_search} tool), \code{"anthropic"}
#'   (Messages \code{web_search}), and \code{"moonshot"} (the
#'   \code{$web_search} builtin); ignored with a warning for other
#'   providers. For \code{"openai"}, the request is routed through the
#'   Responses endpoint so search works on the default model. Moonshot
#'   doesn't expose the query or structured citations, so its
#'   \code{searches} carry \code{query = NA} and \code{citations} is
#'   empty (citations are inlined in the answer text).
#' @param ... Additional parameters passed to the API.
#'
#' @return A list with:
#'   \item{content}{The assistant's response text}
#'   \item{thinking}{Chain-of-thought from reasoning models, or NULL.
#'     Populated from \code{reasoning_content} (DeepSeek, Moonshot Kimi,
#'     vLLM, SGLang), \code{reasoning} (OpenRouter), or Anthropic
#'     \code{thinking} blocks. Normalized across providers.}
#'   \item{finish_reason}{Why generation stopped. \code{"stop"} on a
#'     normal completion, \code{"length"} when truncated by max_tokens.
#'     A reasoning model that returns empty \code{content} with
#'     \code{finish_reason == "length"} ran out of budget mid-thought;
#'     raise \code{max_tokens}.}
#'   \item{model}{Model used}
#'   \item{usage}{Token usage (if available). When the model is in the
#'     bundled price snapshot, also carries \code{cost} as a USD scalar;
#'     Ollama is treated as free (\code{cost = 0}); unknown models leave
#'     \code{cost = NA_real_}. See \code{\link{prices_snapshot_date}}.}
#'   \item{history}{Updated conversation history}
#'
#' @export
#' @examples
#' \dontrun{
#' # Simple chat
#' chat("What is 2+2?")
#'
#' # With system prompt
#' chat("Explain R", system = "You are a helpful programming tutor.")
#'
#' # Continue conversation
#' result <- chat("Hello")
#' chat("Tell me more", history = result$history)
#' }
chat <- function(prompt, model = NULL, system = NULL, history = NULL,
                 temperature = NULL, max_tokens = NULL,
                 provider = c("auto", "openai", "anthropic", "moonshot", "openai_codex",
                              "ollama"),
                 stream = FALSE, cache = c("none", "5m", "1h"),
                 thinking_budget_tokens = NULL, web_search = FALSE, ...) {
    provider <- match.arg(provider)
    cache <- match.arg(cache)

    # Validate the thinking-budget range up front. This is provider-
    # independent input validation and should fail fast, before any
    # provider resolution.
    if (!is.null(thinking_budget_tokens)) {
        .validate_thinking_budget(thinking_budget_tokens, max_tokens)
    }

    # Resolve "auto" to a concrete provider before the Anthropic-only
    # guards below, otherwise they compare against "auto" and wrongly
    # disable cache / thinking_budget_tokens for genuine Anthropic calls.
    if (provider == "auto") {
        provider <- .detect_provider(model)
    }

    # Anthropic-only feature opt-ins emit a one-time warning when a
    # non-default value is passed against another provider so the
    # caller knows the request will be silently degraded.
    if (!identical(cache, "none") && !identical(provider, "anthropic")) {
        warning("`cache` is Anthropic-only; ignoring for provider \"",
                provider, "\".", call. = FALSE)
        cache <- "none"
    }
    if (!is.null(thinking_budget_tokens) && !identical(provider, "anthropic")) {
        warning("`thinking_budget_tokens` is Anthropic-only; ignoring ",
                "for provider \"", provider, "\".", call. = FALSE)
        thinking_budget_tokens <- NULL
    }
    # Provider-native web search. Currently wired for openai_codex; other
    # providers are added incrementally (each has its own native mechanism).
    if (!isFALSE(web_search) && !provider %in% .web_search_providers()) {
        warning("`web_search` is not yet supported for provider \"", provider,
                "\"; ignoring.", call. = FALSE)
        web_search <- FALSE
    }

    # Get provider config
    config <- .get_provider_config(provider)

    # Set default model if not specified
    if (is.null(model)) {
        model <- config$default_model
    }

    # Build messages array
    messages <- list()

    if (!is.null(system)) {
        messages[[length(messages) + 1]] <- list(role = "system",
            content = system)
    }

    if (!is.null(history)) {
        messages <- c(messages, history)
    }

    messages[[length(messages) + 1]] <- list(role = "user", content = prompt)

    # Build request body
    body <- list(model = model, messages = messages, stream = stream)

    if (!is.null(temperature)) {
        body$temperature <- temperature
    }
    if (!is.null(max_tokens)) {
        body$max_tokens <- max_tokens
    }

    if (!isFALSE(web_search)) {
        body$web_search <- web_search
    }

    # Add extra params

    extra <- list(...)
    for (name in names(extra)) {
        body[[name]] <- extra[[name]]
    }

    # Make request
    if (provider == "anthropic") {
        result <- .chat_anthropic(body, config, stream,
                                  cache = cache,
                                  thinking_budget_tokens = thinking_budget_tokens)
    } else if (provider == "openai_codex") {
        result <- .chat_openai_codex(body, config, stream)
    } else if (provider == "openai" && !isFALSE(web_search)) {
        # Server-side web search needs the Responses endpoint; the
        # chat-completions path can't run it on the default models.
        result <- .chat_openai_responses(body, config, stream)
    } else if (provider == "moonshot" && !isFALSE(web_search)) {
        # Moonshot's $web_search builtin round-trips through tool calls;
        # drive that echo loop internally.
        result <- .chat_moonshot_websearch(body, config, stream)
    } else {
        result <- .chat_openai_compatible(body, config, stream)
    }

    # Build updated history
    new_history <- messages
    new_history[[length(new_history) + 1]] <- list(
        role = "assistant",
        content = result$content
    )

    usage <- .augment_usage_with_cost(result$usage, model, provider)

    list(
         content = result$content,
         thinking = result$thinking,
         finish_reason = result$finish_reason,
         model = model,
         usage = usage,
         citations = result$citations,
         searches = result$searches,
         history = new_history
    )
}

# Attach a USD cost field to a provider-shaped usage list. Delegates to
# usage_cost(), which reads the Anthropic or OpenAI-compatible token
# shape and accounts for prompt caching. Cost is appended without
# renaming the existing token fields so callers that already
# destructure usage keep working.
#' @noRd
.augment_usage_with_cost <- function(usage, model, provider) {
    if (is.null(usage)) {
        return(usage)
    }
    usage$cost <- usage_cost(model, provider, usage)
    usage
}

#' OpenAI-compatible chat request
#' @noRd
.chat_openai_compatible <- function(body, config, stream) {
    url <- paste0(config$base_url, config$chat_path)

    # OpenAI deprecated max_tokens in favor of max_completion_tokens
    # and reasoning (o-series) models reject max_tokens entirely. Map
    # for the OpenAI endpoint only; Moonshot and Ollama (which share
    # this helper) still expect max_tokens.
    if (identical(config$provider, "openai") &&
        !is.null(body$max_tokens) &&
        is.null(body$max_completion_tokens)) {
        body$max_completion_tokens <- body$max_tokens
        body$max_tokens <- NULL
    }

    headers <- c("Content-Type" = "application/json")

    if (!is.null(config$api_key) && nchar(config$api_key) > 0) {
        headers["Authorization"] <- paste("Bearer", config$api_key)
    }

    h <- curl::new_handle()
    curl::handle_setopt(h, customrequest = "POST",
                        postfields = jsonlite::toJSON(body, auto_unbox = TRUE))
    curl::handle_setheaders(h, .list = as.list(headers))

    if (stream) {
        .stream_response(url, h)
    } else {
        resp <- curl::curl_fetch_memory(url, handle = h)

        if (resp$status_code >= 400) {
            err <- tryCatch(
                            jsonlite::fromJSON(rawToChar(resp$content)),
                            error = function(e) list(error = list(message = rawToChar(resp$content)))
            )
            stop("API error (", resp$status_code, "): ",
                 err$error$message %||% "Unknown error", call. = FALSE)
        }

        data <- jsonlite::fromJSON(rawToChar(resp$content))

        # Handle both list and data.frame formats from jsonlite
        if (is.data.frame(data$choices)) {
            msg <- data$choices$message
            content <- msg$content[1]
            thinking <- msg$reasoning_content[1] %||% msg$reasoning[1]
            finish_reason <- data$choices$finish_reason[1]
        } else {
            msg <- data$choices[[1]]$message
            content <- msg$content
            thinking <- msg$reasoning_content %||% msg$reasoning
            finish_reason <- data$choices[[1]]$finish_reason
        }

        .warn_if_truncated(content, thinking, finish_reason)

        list(
             content = content,
             thinking = thinking,
             finish_reason = finish_reason,
             usage = data$usage
        )
    }
}

#' Anthropic chat request
#' @noRd
.chat_anthropic <- function(body, config, stream, cache = "none",
                            thinking_budget_tokens = NULL) {
    url <- paste0(config$base_url, config$chat_path)

    # Convert messages format for Anthropic
    system_msg <- NULL
    messages <- list()

    for (msg in body$messages) {
        if (msg$role == "system") {
            system_msg <- msg$content
        } else {
            messages[[length(messages) + 1]] <- msg
        }
    }

    anthropic_body <- list(model = body$model, messages = messages,
                           max_tokens = body$max_tokens %||% 4096)

    if (!is.null(system_msg)) {
        anthropic_body$system <- .anthropic_system_with_cache(system_msg, cache)
    }

    if (!is.null(body$temperature)) {
        anthropic_body$temperature <- body$temperature
    }

    if (!is.null(thinking_budget_tokens)) {
        anthropic_body$thinking <- list(
                                        type = "enabled",
                                        budget_tokens = as.integer(thinking_budget_tokens)
        )
    }

    ws_tool <- .anthropic_web_search_tool(body$web_search)
    if (!is.null(ws_tool)) {
        anthropic_body$tools <- list(ws_tool)
    }

    headers <- c(
                 "Content-Type" = "application/json",
                 "x-api-key" = config$api_key,
                 "anthropic-version" = "2023-06-01"
    )

    h <- curl::new_handle()
    curl::handle_setopt(h,
                        customrequest = "POST",
                        postfields = jsonlite::toJSON(anthropic_body, auto_unbox = TRUE)
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

    data <- jsonlite::fromJSON(rawToChar(resp$content))

    # Handle both data.frame and list formats from jsonlite. content is an
    # ordered list of blocks; pull text out of "text" blocks and thinking
    # out of "thinking" blocks.
    if (is.data.frame(data$content)) {
        types <- data$content$type
        text_blocks <- data$content$text[types == "text"]
        thinking_blocks <- data$content$thinking[types == "thinking"]
    } else {
        types <- vapply(data$content, function(b) b$type %||% "", character(1))
        text_blocks <- vapply(data$content[types == "text"],
                              function(b) b$text %||% "", character(1))
        thinking_blocks <- vapply(data$content[types == "thinking"],
                                  function(b) b$thinking %||% "", character(1))
    }

    if (length(text_blocks)) {
        content <- paste(text_blocks, collapse = "\n")
    } else {
        content <- ""
    }
    thinking <- if (length(thinking_blocks)) {
        paste(thinking_blocks, collapse = "\n")
    } else {
        NULL
    }
    finish_reason <- .normalize_anthropic_stop_reason(data$stop_reason)

    .warn_if_truncated(content, thinking, finish_reason)

    # Web-search citations/queries need the block-level structure, so re-parse
    # the content as a list (the data.frame parse above flattens nested arrays).
    search_info <- if (isFALSE(body$web_search %||% FALSE)) {
        list(citations = list(), searches = list())
    } else {
        blocks <- jsonlite::fromJSON(rawToChar(resp$content),
                                     simplifyVector = FALSE)$content
        .anthropic_search_blocks(blocks)
    }

    list(
         content = content,
         thinking = thinking,
         finish_reason = finish_reason,
         usage = data$usage,
         citations = search_info$citations,
         searches = search_info$searches
    )
}

# Map Anthropic's stop_reason to OpenAI-style finish_reason so callers see
# one vocabulary across providers. "max_tokens" is Anthropic's name for
# what OpenAI calls "length"; "end_turn" maps to "stop". Other values
# ("stop_sequence", "tool_use", "pause_turn", "refusal") pass through.
.normalize_anthropic_stop_reason <- function(stop_reason) {
    if (is.null(stop_reason) || !nzchar(stop_reason)) {
        return(NULL)
    }
    switch(stop_reason, "end_turn" = "stop", "max_tokens" = "length",
           stop_reason)
}

# Surface the silent-empty-content failure mode of reasoning models. When
# the model burns its budget on chain-of-thought without ever emitting a
# user-facing answer, callers otherwise see content="" and assume the
# model decided to say nothing.
.warn_if_truncated <- function(content, thinking, finish_reason) {
    if (identical(finish_reason, "length") &&
        !nzchar(content %||% "") &&
        nzchar(thinking %||% "")) {
        warning("Model truncated mid-reasoning; partial chain-of-thought ",
                "available in $thinking. Increase max_tokens.", call. = FALSE)
    }
}

#' Stream response with live output
#' @noRd
.stream_response <- function(url, handle) {
    full_content <- ""
    full_thinking <- ""
    finish_reason <- NULL

    callback <- function(data) {
        lines <- strsplit(rawToChar(data), "\n")[[1]]
        for (line in lines) {
            if (startsWith(line, "data: ") && line != "data: [DONE]") {
                json_str <- substring(line, 7)
                tryCatch({
                    chunk <- jsonlite::fromJSON(json_str)
                    choice <- chunk$choices[[1]]
                    delta <- choice$delta$content
                    if (!is.null(delta)) {
                        cat(delta)
                        full_content <<- paste0(full_content, delta)
                    }
                    think_delta <- choice$delta$reasoning_content %||%
                    choice$delta$reasoning
                    if (!is.null(think_delta)) {
                        full_thinking <<- paste0(full_thinking, think_delta)
                    }
                    if (!is.null(choice$finish_reason)) {
                        finish_reason <<- choice$finish_reason
                    }
                }, error = function(e) NULL)
            }
        }
        length(data)
    }

    curl::handle_setopt(handle, writefunction = callback)
    curl::curl_fetch_memory(url, handle = handle)
    cat("\n")

    if (nzchar(full_thinking)) {
        thinking <- full_thinking
    } else {
        thinking <- NULL
    }
    .warn_if_truncated(full_content, thinking, finish_reason)

    list(content = full_content, thinking = thinking,
         finish_reason = finish_reason, usage = NULL)
}

#' Null coalescing operator
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) {
    y
} else {
    x
}
