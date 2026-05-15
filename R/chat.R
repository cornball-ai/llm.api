# Core chat functionality

#' Chat with an LLM
#'
#' Send a message to a Large Language Model and get a response.
#'
#' @param prompt Character. The user message to send.
#' @param model Character. Model name (e.g., "gpt-4o", "claude-sonnet-4-6", "llama3.2").
#' @param system Character or NULL. System prompt to set context.
#' @param history List or NULL. Previous conversation turns.
#' @param temperature Numeric or NULL. Sampling temperature (0-2).
#' @param max_tokens Integer or NULL. Maximum tokens in response.
#' @param provider Character. Provider: "auto", "openai", "anthropic",
#'   "moonshot", or "ollama".
#' @param stream Logical. Stream the response (prints as it arrives).
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
                 provider = c("auto", "openai", "anthropic", "moonshot", "ollama"),
                 stream = FALSE, ...) {
    provider <- match.arg(provider)

    # Auto-detect provider from model name or base URL

    if (provider == "auto") {
        provider <- .detect_provider(model)
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

    # Add extra params

    extra <- list(...)
    for (name in names(extra)) {
        body[[name]] <- extra[[name]]
    }

    # Make request
    if (provider == "anthropic") {
        result <- .chat_anthropic(body, config, stream)
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
         history = new_history
    )
}

# Attach a USD cost field to a provider-shaped usage list. Anthropic
# returns input_tokens/output_tokens, OpenAI-compatible returns
# prompt_tokens/completion_tokens; we read whichever is present. Cost
# is appended without renaming the existing token fields so callers
# that already destructure usage keep working.
#' @noRd
.augment_usage_with_cost <- function(usage, model, provider) {
    if (is.null(usage)) {
        return(usage)
    }
    input_tokens <- usage$input_tokens %||% usage$prompt_tokens
    output_tokens <- usage$output_tokens %||% usage$completion_tokens
    usage$cost <- .cost_for(model, provider, input_tokens, output_tokens)
    usage
}

#' OpenAI-compatible chat request
#' @noRd
.chat_openai_compatible <- function(body, config, stream) {
    url <- paste0(config$base_url, config$chat_path)

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
.chat_anthropic <- function(body, config, stream) {
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
        anthropic_body$system <- system_msg
    }

    if (!is.null(body$temperature)) {
        anthropic_body$temperature <- body$temperature
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

    list(
         content = content,
         thinking = thinking,
         finish_reason = finish_reason,
         usage = data$usage
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

