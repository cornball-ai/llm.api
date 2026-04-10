# Provider configurations

#' Detect provider from model name or config
#' @noRd
.detect_provider <- function(model) {
  base <- .get_base()

  # Check if model is a local file path
  if (!is.null(model) && grepl("\\.gguf$", model, ignore.case = TRUE)) {
    return("local")
  }

  # Check base URL first
  if (!is.null(base)) {
    if (grepl("moonshot|kimi", base, ignore.case = TRUE)) return("moonshot")
    if (grepl("anthropic", base, ignore.case = TRUE)) return("anthropic")
    if (grepl("openai", base, ignore.case = TRUE)) return("openai")
    if (grepl("localhost|127\\.0\\.0\\.1", base)) return("ollama")
  }

  # Check model name
  if (!is.null(model)) {
    if (grepl("^claude", model, ignore.case = TRUE)) return("anthropic")
    if (grepl("^kimi|^moonshot-v1", model, ignore.case = TRUE)) return("moonshot")
    if (grepl("^(llama|mistral|phi|qwen|gemma|codellama|deepseek)",
              model, ignore.case = TRUE)) {
      return("ollama")
    }
    # Check if model is installed in Ollama
    ollama_models <- tryCatch(
      list_ollama_models()$name,
      error = function(e) character(0)
    )
    if (model %in% ollama_models) return("ollama")
    if (grepl("^gpt|^o1|^o3", model, ignore.case = TRUE)) return("openai")
  }

  # Default to OpenAI-compatible
  "openai"
}

#' Get provider configuration
#' @noRd
.get_provider_config <- function(provider) {
  base <- .get_base()
  key <- .get_key()

  switch(provider,
    openai = list(
      base_url = base %||% "https://api.openai.com",
      chat_path = "/v1/chat/completions",
      api_key = .get_key("openai"),
      default_model = "gpt-4o-mini"
    ),
    anthropic = list(
      base_url = base %||% "https://api.anthropic.com",
      chat_path = "/v1/messages",
      api_key = .get_key("anthropic"),
      default_model = "claude-3-5-sonnet-latest"
    ),
    moonshot = list(
      base_url = base %||% "https://api.moonshot.ai",
      chat_path = "/v1/chat/completions",
      api_key = .get_key("moonshot"),
      default_model = "kimi-k2"
    ),
    ollama = list(
      base_url = base %||% "http://localhost:11434",
      chat_path = "/v1/chat/completions",
      api_key = NULL,
      default_model = "llama3.2"
    ),
    stop("Unknown provider: ", provider, call. = FALSE)
  )
}

#' Chat with OpenAI
#'
#' Convenience wrapper for 'OpenAI' models.
#'
#' @inheritParams chat
#' @return The assistant's response as a character string, or a list when
#'   \code{history} is in use. See \code{\link{chat}} for details.
#' @export
#' @examples
#' \dontrun{
#' chat_openai("Explain quantum computing")
#' chat_openai("Write a haiku", model = "gpt-4o")
#' }
chat_openai <- function(
  prompt,
  model = "gpt-4o-mini",
  ...
) {
  chat(prompt, model = model, provider = "openai", ...)
}

#' Chat with Anthropic Claude
#'
#' Convenience wrapper for 'Anthropic' 'Claude' models.
#'
#' @inheritParams chat
#' @return The assistant's response as a character string, or a list when
#'   \code{history} is in use. See \code{\link{chat}} for details.
#' @export
#' @examples
#' \dontrun{
#' chat_claude("Explain the theory of relativity")
#' chat_claude("Write a poem", model = "claude-3-5-haiku-latest")
#' }
chat_claude <- function(
  prompt,
  model = "claude-3-5-sonnet-latest",
  ...
) {
  chat(prompt, model = model, provider = "anthropic", ...)
}

#' Chat with Ollama
#'
#' Convenience wrapper for local 'Ollama' models.
#'
#' @inheritParams chat
#' @return The assistant's response as a character string, or a list when
#'   \code{history} is in use. See \code{\link{chat}} for details.
#' @export
#' @examples
#' \dontrun{
#' chat_ollama("What is machine learning?")
#' chat_ollama("Explain Docker", model = "mistral")
#' }
chat_ollama <- function(
  prompt,
  model = "llama3.2",
  ...
) {
  chat(prompt, model = model, provider = "ollama", ...)
}

#' List Ollama models
#'
#' List all models downloaded in Ollama.
#'
#' @param base_url Character. Ollama server URL (default: http://localhost:11434).
#'
#' @return A data frame with model information (name, size, modified).
#' @export
#' @examples
#' \dontrun{
#' list_ollama_models()
#' }
list_ollama_models <- function(base_url = "http://localhost:11434") {
  url <- paste0(base_url, "/api/tags")

  h <- curl::new_handle()
  resp <- tryCatch(
    curl::curl_fetch_memory(url, handle = h),
    error = function(e) {
      stop("Cannot connect to Ollama at ", base_url,
        ". Is Ollama running?", call. = FALSE)
    }
  )

  if (resp$status_code >= 400) {
    stop("Ollama API error (", resp$status_code, ")", call. = FALSE)
  }

  data <- jsonlite::fromJSON(rawToChar(resp$content))

  if (is.null(data$models) || length(data$models) == 0) {
    message("No models found. Use 'ollama pull <model>' to download models.")
    return(invisible(data.frame(name = character(), size = numeric(), modified = character())))
  }

  data.frame(
    name = data$models$name,
    size = round(data$models$size / 1e9, 1),
    modified = as.character(as.POSIXct(data$models$modified_at))
  )
}
