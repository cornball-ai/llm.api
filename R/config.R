# API Configuration

#' Set LLM API Base URL
#'
#' Stores a base URL in the \code{llm.api.api_base} option, which
#' \code{\link{chat}} uses as the default endpoint.
#'
#' @param url Character. Base URL for the API endpoint.
#' @return The previous value of the option, invisibly.
#' @export
#' @examples
#' old <- llm_base("http://localhost:11434")  # 'Ollama'
#' llm_base(old)  # restore
llm_base <- function(url) {
  old <- getOption("llm.api.api_base")
  options(llm.api.api_base = url)
  invisible(old)
}

#' Set LLM API Key
#'
#' Stores an API key in the \code{llm.api.api_key} option, which
#' \code{\link{chat}} prefers over environment variables.
#'
#' @param key Character. API key for authentication.
#' @return The previous value of the option, invisibly.
#' @export
#' @examples
#' old <- llm_key("sk-not-a-real-key")
#' llm_key(old)  # restore
llm_key <- function(key) {
  old <- getOption("llm.api.api_key")
  options(llm.api.api_key = key)
  invisible(old)
}

#' Get API Base URL
#' @noRd
.get_base <- function() {

  getOption("llm.api.api_base")
}

#' Get API Key
#' @noRd
.get_key <- function(provider = NULL) {
  key <- getOption("llm.api.api_key")
  if (is.null(key) || nchar(key) == 0) {
    env_vars <- switch(provider %||% "",
      anthropic = c("ANTHROPIC_API_KEY"),
      openai = c("OPENAI_API_KEY"),
      moonshot = c("MOONSHOT_API_KEY", "OPENAI_API_KEY"),
      c("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "MOONSHOT_API_KEY")
    )

    for (env_var in env_vars) {
      key <- Sys.getenv(env_var, "")
      if (nchar(key) > 0) {
        break
      }
    }
  }
  key
}
