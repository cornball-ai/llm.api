# Per-call USD cost from token counts.
#
# `.PRICES` is a baked-in snapshot of BerriAI/litellm's
# model_prices_and_context_window.json (see data-raw/prices.R).
# Lookup is offline; CRAN-friendly. Refresh by re-running the snapshot
# script.

#' Look up cost in USD for a single API call.
#'
#' Returns `0` for ollama (local, no API charge), a positive number
#' when the model is in the snapshot, or `NA_real_` when it isn't.
#' Cached input tokens are not discounted at this layer; callers that
#' care about Anthropic prompt caching can refine downstream.
#'
#' @param model Character. Model id as sent to the provider.
#' @param provider Character. "anthropic", "openai", "moonshot", or
#'   "ollama".
#' @param input_tokens Integer. Prompt tokens from the response.
#' @param output_tokens Integer. Completion tokens from the response.
#' @return Numeric scalar (USD) or `NA_real_` when the model isn't in
#'   the price snapshot.
#' @noRd
.cost_for <- function(model, provider, input_tokens, output_tokens) {
    if (identical(provider, "ollama")) {
        return(0)
    }
    if (is.null(model) || !nzchar(model)) {
        return(NA_real_)
    }

    prices <- .price_lookup(model, provider)
    if (is.null(prices)) {
        return(NA_real_)
    }

    if (is.null(input_tokens) || is.na(input_tokens)) {
        inp <- 0
    } else {
        inp <- as.numeric(input_tokens)
    }

    if (is.null(output_tokens) || is.na(output_tokens)) {
        out <- 0
    } else {
        out <- as.numeric(output_tokens)
    }

    inp * prices$input + out * prices$output
}

# Find a model in `.PRICES`. Tries bare model id first, then a
# provider-prefixed form ("openai/gpt-4o", "moonshot/kimi-k2.5") since
# litellm namespaces models that share a basename across providers.
#' @noRd
.price_lookup <- function(model, provider) {
    rec <- .PRICES[[model]]
    if (!is.null(rec)) {
        return(rec)
    }
    if (!is.null(provider) && nzchar(provider)) {
        rec <- .PRICES[[paste0(provider, "/", model)]]
        if (!is.null(rec)) {
            return(rec)
        }
    }
    NULL
}

#' Price snapshot date
#'
#' Returns the date (`YYYY-MM-DD`) the bundled price table was
#' snapshotted from BerriAI/litellm. Use this to decide when a
#' refresh is due.
#'
#' @return Character. ISO date string.
#' @export
#' @examples
#' \dontrun{
#' prices_snapshot_date()
#' }
prices_snapshot_date <- function() {
    .PRICES_SNAPSHOT_DATE
}

