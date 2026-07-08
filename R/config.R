# API Configuration

# Canonical option names. The `<pkgname>_base` / `<pkgname>_key` form
# matches the sibling API packages (tts.api_base, stt.api_base,
# xtx.api_base), so llm.api reads the same way. The pre-0.2.0 names
# (llm.api.api_base / llm.api.api_key, with the doubled "api") are
# still read as a deprecated fallback; see .get_base() / .get_key().
.opt_base <- "llm.api_base"
.opt_key <- "llm.api_key"
.opt_base_legacy <- "llm.api.api_base"
.opt_key_legacy <- "llm.api.api_key"

#' Set LLM API Base URL
#'
#' Stores a base URL in the \code{llm.api_base} option, which
#' \code{\link{chat}} uses as the default endpoint.
#'
#' @param url Character. Base URL for the API endpoint.
#' @return The previous value of the option, invisibly.
#' @export
#' @examples
#' old <- llm_base("http://localhost:11434")  # 'Ollama'
#' llm_base(old)  # restore
llm_base <- function(url) {
    old <- .get_base()
    options(structure(list(url), names = .opt_base))
    invisible(old)
}

#' Set LLM API Key
#'
#' Stores an API key in the \code{llm.api_key} option, which
#' \code{\link{chat}} prefers over environment variables.
#'
#' @param key Character. API key for authentication.
#' @return The previous value of the option, invisibly.
#' @export
#' @examples
#' old <- llm_key("sk-not-a-real-key")
#' llm_key(old)  # restore
llm_key <- function(key) {
    old <- .get_key_option()
    options(structure(list(key), names = .opt_key))
    invisible(old)
}

# Read an option that was renamed in 0.2.0: prefer the canonical name,
# fall back to the pre-0.2.0 name with a one-time deprecation warning
# per session so a stale .Rprofile keeps working while nudging callers
# to migrate.
.deprecated_opt_warned <- new.env(parent = emptyenv())
.get_renamed_option <- function(canonical, legacy) {
    val <- getOption(canonical)
    if (!is.null(val)) {
        return(val)
    }
    val <- getOption(legacy)
    if (!is.null(val) && is.null(.deprecated_opt_warned[[legacy]])) {
        .deprecated_opt_warned[[legacy]] <- TRUE
        warning("Option \"", legacy, "\" is deprecated; use \"", canonical,
                "\" instead (e.g. via llm_base() / llm_key()).", call. = FALSE)
    }
    val
}

#' Get API Base URL
#' @noRd
.get_base <- function() {
    .get_renamed_option(.opt_base, .opt_base_legacy)
}

# The option-only key (no env fallback), for llm_key()'s old-value return.
#' @noRd
.get_key_option <- function() {
    .get_renamed_option(.opt_key, .opt_key_legacy)
}

#' Get API Key
#' @noRd
.get_key <- function(provider = NULL) {
    key <- .get_key_option()
    if (is.null(key) || nchar(key) == 0) {
        env_vars <- switch(provider %||% "",
                           anthropic = c("ANTHROPIC_API_KEY"),
                           openai = c("OPENAI_API_KEY"),
                           moonshot = c("MOONSHOT_API_KEY", "OPENAI_API_KEY"),
                           openai_codex = c("OPENAI_CODEX_ACCESS_TOKEN"),
                           openai_compatible = c("OPENAI_COMPATIBLE_API_KEY",
                "OPENAI_API_KEY"),
                           c("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "MOONSHOT_API_KEY",
                             "OPENAI_CODEX_ACCESS_TOKEN")
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
