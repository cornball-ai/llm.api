# Core chat functionality

#' Chat with an LLM
#'
#' Send a message to a Large Language Model and get a response.
#'
#' @param prompt Character. The user message to send.
#' @param model Character. Model name (e.g., "gpt-4o", "claude-3-5-sonnet-latest", "llama3.2").
#' @param system Character or NULL. System prompt to set context.
#' @param history List or NULL. Previous conversation turns.
#' @param temperature Numeric or NULL. Sampling temperature (0-2).
#' @param max_tokens Integer or NULL. Maximum tokens in response.
#' @param provider Character. Provider: "auto", "openai", "anthropic", "ollama".
#' @param stream Logical. Stream the response (prints as it arrives).
#' @param ... Additional parameters passed to the API.
#'
#' @return A list with:
#'   \item{content}{The assistant's response text}
#'   \item{model}{Model used}
#'   \item{usage}{Token usage (if available)}
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
chat <- function(
  prompt,
  model = NULL,
  system = NULL,
  history = NULL,
  temperature = NULL,
  max_tokens = NULL,
  provider = c("auto", "openai", "anthropic", "ollama", "local"),
  stream = FALSE,
  ...
) {

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
    messages[[length(messages) + 1]] <- list(role = "system", content = system)
  }

  if (!is.null(history)) {
    messages <- c(messages, history)
  }

  messages[[length(messages) + 1]] <- list(role = "user", content = prompt)

  # Build request body
  body <- list(
    model = model,
    messages = messages,
    stream = stream
  )

  if (!is.null(temperature)) body$temperature <- temperature
  if (!is.null(max_tokens)) body$max_tokens <- max_tokens

  # Add extra params

  extra <- list(...)
  for (name in names(extra)) {
    body[[name]] <- extra[[name]]
  }

  # Make request
  if (provider == "local") {
    # Use localLLM for direct llama.cpp inference
    result <- chat_local(
      prompt = prompt,
      model = model,
      system = system,
      n_predict = max_tokens %||% 256,
      temperature = temperature %||% 0.7,
      ...
    )
    result$usage <- NULL
  } else if (provider == "anthropic") {
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

  list(
    content = result$content,
    model = model,
    usage = result$usage,
    history = new_history
  )
}

#' OpenAI-compatible chat request
#' @noRd
.chat_openai_compatible <- function(
  body,
  config,
  stream
) {
  url <- paste0(config$base_url, config$chat_path)

  headers <- c(
    "Content-Type" = "application/json"
  )

  if (!is.null(config$api_key) && nchar(config$api_key) > 0) {
    headers["Authorization"] <- paste("Bearer", config$api_key)
  }

  h <- curl::new_handle()
  curl::handle_setopt(h,
    customrequest = "POST",
    postfields = jsonlite::toJSON(body, auto_unbox = TRUE)
  )
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
    content <- if (is.data.frame(data$choices)) {
      data$choices$message$content[1]
    } else {
      data$choices[[1]]$message$content
    }

    list(
      content = content,
      usage = data$usage
    )
  }
}

#' Anthropic chat request
#' @noRd
.chat_anthropic <- function(
  body,
  config,
  stream
) {
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

  anthropic_body <- list(
    model = body$model,
    messages = messages,
    max_tokens = body$max_tokens %||% 4096
  )

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

  list(
    content = data$content[[1]]$text,
    usage = data$usage
  )
}

#' Stream response with live output
#' @noRd
.stream_response <- function(
  url,
  handle
) {
  full_content <- ""

  callback <- function(data) {
    lines <- strsplit(rawToChar(data), "\n") [[1]]
    for (line in lines) {
      if (startsWith(line, "data: ") && line != "data: [DONE]") {
        json_str <- substring(line, 7)
        tryCatch({
            chunk <- jsonlite::fromJSON(json_str)
            delta <- chunk$choices[[1]]$delta$content
            if (!is.null(delta)) {
              cat(delta)
              full_content <<- paste0(full_content, delta)
            }
          }, error = function(e) NULL)
      }
    }
    length(data)
  }

  curl::handle_setopt(handle, writefunction = callback)
  curl::curl_fetch_memory(url, handle = handle)
  cat("\n")

  list(content = full_content, usage = NULL)
}

#' Null coalescing operator
#' @noRd
`%||%` <- function(
  x,
  y
) if (is.null(x)) y else x

