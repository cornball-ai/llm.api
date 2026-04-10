# API Configuration

#' Set LLM API Base URL
#'
#' @param url Base URL for the API endpoint
#' @return Invisibly returns the previous value
#' @export
#' @examples
#' \dontrun{
#' llm_base("http://localhost:11434")  # Ollama
#' llm_base("https://api.openai.com")
#' }
llm_base <- function(url) {
  old <- getOption("llm.api.api_base")
  options(llm.api.api_base = url)
  invisible(old)
}

#' Set LLM API Key
#'
#' @param key API key for authentication
#' @return Invisibly returns the previous value
#' @export
#' @examples
#' \dontrun{
#' llm_key("sk-...")
#' }
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
