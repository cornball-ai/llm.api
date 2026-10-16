#' List provider model identifiers
#'
#' Queries the provider's model catalog without generating a response.
#' OpenAI Codex reads the local Codex model cache instead; those entries
#' reflect its last refresh, not a new entitlement check. Catalog membership
#' does not guarantee tool support. Unsupported catalogs raise an error so
#' callers can fall back to their configured models.
#'
#' @param provider Provider name.
#' @param base_url Optional endpoint override, with the same convention as
#'   \code{\link{llm_base}}.
#' @param timeout Request timeout in seconds.
#' @param codex_cache Optional Codex model-cache path. Defaults to
#'   \code{models_cache.json} under \code{CODEX_HOME} or \code{~/.codex}.
#' @return Character vector of model identifiers. The \code{source} attribute
#'   is \code{"provider"} or \code{"Codex cache"}.
#' @examples
#' \dontrun{
#' list_models("openai")
#' list_models("openai_codex")
#' }
#' @export
list_models <- function(provider, base_url = NULL, timeout = 5,
                        codex_cache = NULL) {
    if (identical(provider, "openai_codex")) {
        path <- codex_cache %||% file.path(
            Sys.getenv("CODEX_HOME", path.expand("~/.codex")), "models_cache.json")
        cache <- jsonlite::fromJSON(path, simplifyVector = FALSE)
        models <- Filter(function(x) identical(x$visibility, "list"), cache$models)
        ids <- vapply(models, function(x) x$slug %||% "", character(1))
        return(structure(unique(ids[nzchar(ids)]), source = "Codex cache"))
    }
    if (!provider %in% c("openai", "anthropic", "moonshot", "ollama",
                         "openai_compatible")) {
        stop("No model catalog for provider: ", provider, call. = FALSE)
    }
    config <- .get_provider_config(provider)
    base <- sub("/+$", "", base_url %||% config$base_url %||% "")
    if (!nzchar(base)) {
        stop("A base URL is required for model discovery.", call. = FALSE)
    }
    headers <- list(Accept = "application/json")
    path <- if (provider == "ollama") "/api/tags" else if
        (provider == "openai_compatible") "/models" else "/v1/models"
    if (provider == "anthropic") {
        headers[["x-api-key"]] <- config$api_key
        headers[["anthropic-version"]] <- "2023-06-01"
    } else if (!is.null(config$api_key) && nzchar(config$api_key)) {
        headers$Authorization <- paste("Bearer", config$api_key)
    }
    ids <- character()
    cursor <- NULL
    repeat {
        url <- paste0(base, path)
        if (provider == "anthropic") {
            url <- paste0(url, "?limit=1000", if (!is.null(cursor))
                paste0("&after_id=", curl::curl_escape(cursor)))
        }
        payload <- .models_get(url, headers, timeout)
        entries <- if (provider == "ollama") payload$models else payload$data
        if (!is.list(entries)) {
            stop("Invalid provider model catalog.", call. = FALSE)
        }
        ids <- c(ids, vapply(entries, function(x) {
            if (provider == "ollama") x$name %||% "" else x$id %||% ""
        }, character(1)))
        if (provider != "anthropic" || !isTRUE(payload$has_more)) break
        next_cursor <- payload$last_id
        if (is.null(next_cursor) || identical(next_cursor, cursor)) {
            stop("Invalid model catalog pagination.", call. = FALSE)
        }
        cursor <- next_cursor
    }
    structure(sort(unique(ids[nzchar(ids)])), source = "provider")
}

.models_get <- function(url, headers, timeout) {
    handle <- curl::new_handle(timeout = timeout, connecttimeout = timeout)
    curl::handle_setheaders(handle, .list = headers)
    response <- curl::curl_fetch_memory(url, handle = handle)
    if (response$status_code < 200L || response$status_code >= 300L) {
        stop("Model catalog request failed (HTTP ", response$status_code,
             ").", call. = FALSE)
    }
    jsonlite::fromJSON(rawToChar(response$content), simplifyVector = FALSE)
}
