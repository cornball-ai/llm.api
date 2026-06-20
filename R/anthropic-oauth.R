# Anthropic Claude subscription (OAuth) provider
#
# The Messages API request/response handling lives in the shared anthropic path
# (.chat_anthropic / .agent_anthropic). This file adds the subscription-OAuth
# variant: a credentials adapter over tinyoauth's Claude route plus the header
# helper both paths use to pick OAuth (Authorization: Bearer + the oauth beta
# header) over an x-api-key. The OAuth flow itself -- PKCE login, caching,
# refresh -- lives in tinyoauth (see tinyoauth::oauth_token_anthropic).

#' Is this an Anthropic-family provider (API key or subscription OAuth)?
#'
#' Both providers speak the same Messages API, so caching, thinking, usage
#' parsing, and cost all treat them alike.
#' @noRd
.is_anthropic <- function(provider) {
    provider %in% c("anthropic", "anthropic_oauth")
}

#' Anthropic request headers (API key or subscription OAuth)
#'
#' Returns the header vector for a Messages API request. When the provider
#' config carries a \code{credentials} function (the \code{anthropic_oauth}
#' provider), its headers are used (a bearer token plus the OAuth beta header);
#' otherwise the \code{x-api-key} header is used.
#' @noRd
.anthropic_headers <- function(config) {
    base <- c("Content-Type" = "application/json",
              "anthropic-version" = "2023-06-01")
    if (is.function(config$credentials)) {
        c(base, unlist(config$credentials()))
    } else {
        c(base, "x-api-key" = config$api_key)
    }
}

#' Anthropic Claude subscription (OAuth) credentials
#'
#' Builds a zero-argument credentials function for the \code{anthropic_oauth}
#' provider. Tokens are obtained, cached, and refreshed by tinyoauth (see
#' \code{\link[tinyoauth]{oauth_token_anthropic}}); this returns the request
#' headers (\code{Authorization} and the OAuth beta header) for the current
#' token.
#'
#' The \code{ANTHROPIC_OAUTH_ACCESS_TOKEN} environment variable overrides the
#' cache when set.
#'
#' @param access_token Optional access token. If omitted, read from
#'   \code{ANTHROPIC_OAUTH_ACCESS_TOKEN}, then from the tinyoauth cache.
#' @return A zero-argument credentials function returning request headers.
#' @export
anthropic_oauth_credentials <- function(access_token = Sys.getenv("ANTHROPIC_OAUTH_ACCESS_TOKEN",
        "")) {
    if (identical(access_token, "")) {
        access_token <- NULL
    }

    function() {
        at <- access_token
        if (is.null(at)) {
            tok <- tinyoauth::oauth_token_anthropic(login = FALSE)
            if (is.null(tok)) {
                stop("No Claude OAuth credentials available. Run ",
                     "claude_oauth_login() (or set ANTHROPIC_OAUTH_ACCESS_TOKEN).",
                     call. = FALSE)
            }
            at <- tok$access_token
        }
        list(Authorization = paste("Bearer", at),
             `anthropic-beta` = "oauth-2025-04-20")
    }
}

#' Log in to Claude with the subscription OAuth flow
#'
#' Runs tinyoauth's Claude (Claude Code) login flow, caching the token for reuse
#' across sessions, and returns an \code{\link{anthropic_oauth_credentials}}
#' callback. The login is manual-paste: open the printed URL, approve, and paste
#' the displayed code back.
#'
#' @param open_url Logical. Whether to open the authorization URL in a browser.
#' @return A zero-argument credentials function, invisibly. You don't normally
#'   need it: the cached token is picked up automatically by
#'   \code{chat(provider = "anthropic_oauth")} and \code{chat_claude_oauth()}.
#' @export
claude_oauth_login <- function(open_url = interactive()) {
    tinyoauth::oauth_token_anthropic(open_url = open_url)
    message("Logged in to Claude. Token cached; no need to log in again.")
    invisible(anthropic_oauth_credentials())
}

#' Chat with Claude on a subscription (OAuth)
#'
#' Convenience wrapper for Claude-subscription-backed models via the OAuth
#' token from \code{\link{claude_oauth_login}} (no API key required).
#'
#' @inheritParams chat
#' @return The assistant's response as a list. See \code{\link{chat}}.
#' @export
#' @examples
#' \dontrun{
#' claude_oauth_login()
#' chat_claude_oauth("Explain the theory of relativity")
#' }
chat_claude_oauth <- function(prompt, model = "claude-sonnet-4-6", ...) {
    chat(prompt, model = model, provider = "anthropic_oauth", ...)
}
