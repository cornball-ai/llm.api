# Stateful chat session wrapper
# Provides ellmer-compatible interface for use with shinychat

#' Create a stateful chat session
#'
#' Creates a chat session that maintains conversation history internally.
#' Returns a list of functions for interacting with the session.
#'
#' @param model Character. Model name.
#' @param system_prompt Character or NULL. System prompt.
#' @param provider Character. Provider: "openai", "anthropic", "ollama".
#' @param ... Additional parameters passed to chat().
#'
#' @return A list with functions:
#'   \item{chat(message)}{Send a message, returns response text}
#'   \item{stream(message)}{Stream a response, returns response text}
#'   \item{stream_async(message)}{Async stream for shinychat (returns string)}
#'   \item{last_turn()}{Get the last response as list(role, text)}
#'   \item{history()}{Get full conversation history}
#'   \item{clear()}{Clear conversation history}
#'
#' @export
#' @examples
#' \dontrun{
#' # Create a session
#' session <- chat_session(model = "gpt-4o", system_prompt = "You are helpful.")
#'
#' # Chat (history maintained automatically)
#' response <- session$chat("Hello")
#' response2 <- session$chat("Tell me more")
#'
#' # Get last response
#' last <- session$last_turn()
#' last$text
#'
#' # Clear and start over
#' session$clear()
#' }
chat_session <- function(
  model = NULL,
  system_prompt = NULL,
  provider = c("openai", "anthropic", "ollama"),
  ...
) {
  provider <- match.arg(provider)

 # Internal state
  .history <- list()
  .system <- system_prompt
  .model <- model
  .provider <- provider
  .extra <- list(...)
  .last_response <- NULL

  # Chat method - send message, return response text
  chat_fn <- function(message) {
    result <- do.call(chat, c(
      list(
        prompt = message,
        model = .model,
        system = if (length(.history) == 0) .system else NULL,
        history = .history,
        provider = .provider,
        stream = FALSE
      ),
      .extra
    ))

    .history <<- result$history
    .last_response <<- list(role = "assistant", text = result$content)

    result$content
  }

  # Stream method - stream response, return full text
  stream_fn <- function(message) {
    result <- do.call(chat, c(
      list(
        prompt = message,
        model = .model,
        system = if (length(.history) == 0) .system else NULL,
        history = .history,
        provider = .provider,
        stream = TRUE
      ),
      .extra
    ))

    .history <<- result$history
    .last_response <<- list(role = "assistant", text = result$content)

    result$content
  }

  # Async stream for shinychat compatibility
  # Returns string since true async requires coro package
  stream_async_fn <- function(message) {
    chat_fn(message)
  }

  # Get last turn
  last_turn_fn <- function() {
    .last_response
  }

  # Get history
  history_fn <- function() {
    .history
  }

  # Clear history
  clear_fn <- function() {
    .history <<- list()
    .last_response <<- NULL
    invisible(NULL)
  }

  list(
    chat = chat_fn,
    stream = stream_fn,
    stream_async = stream_async_fn,
    last_turn = last_turn_fn,
    history = history_fn,
    clear = clear_fn
  )
}

#' Create OpenAI chat session
#'
#' Convenience wrapper for chat_session with OpenAI provider.
#'
#' @param model Character. Model name (default: "gpt-4o").
#' @param system_prompt Character or NULL. System prompt.
#' @param ... Additional parameters passed to chat_session().
#'
#' @return A chat session list.
#' @export
chat_session_openai <- function(model = "gpt-4o", system_prompt = NULL, ...) {
  chat_session(model = model, system_prompt = system_prompt, provider = "openai", ...)
}

#' Create Anthropic chat session
#'
#' Convenience wrapper for chat_session with Anthropic provider.
#'
#' @param model Character. Model name (default: "claude-sonnet-4-20250514").
#' @param system_prompt Character or NULL. System prompt.
#' @param ... Additional parameters passed to chat_session().
#'
#' @return A chat session list.
#' @export
chat_session_anthropic <- function(model = "claude-sonnet-4-20250514", system_prompt = NULL, ...) {
  chat_session(model = model, system_prompt = system_prompt, provider = "anthropic", ...)
}

#' Create Ollama chat session
#'
#' Convenience wrapper for chat_session with Ollama provider.
#'
#' @param model Character. Model name (default: "llama3.2").
#' @param system_prompt Character or NULL. System prompt.
#' @param ... Additional parameters passed to chat_session().
#'
#' @return A chat session list.
#' @export
chat_session_ollama <- function(model = "llama3.2", system_prompt = NULL, ...) {
  chat_session(model = model, system_prompt = system_prompt, provider = "ollama", ...)
}
