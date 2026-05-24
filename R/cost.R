# Per-call USD cost from token counts.
#
# `.PRICES` is a baked-in snapshot of BerriAI/litellm's
# model_prices_and_context_window.json (see data-raw/prices.R).
# Lookup is offline; CRAN-friendly. Refresh by re-running the snapshot
# script.

# Coerce a possibly-NULL / possibly-NA token count to a numeric scalar,
# treating absent or NA as zero.
#' @noRd
.num0 <- function(x) {
    if (is.null(x) || (length(x) == 1L && is.na(x))) {
        return(0)
    }
    as.numeric(x)
}

#' Look up cost in USD for a single API call.
#'
#' Returns `0` for ollama (local, no API charge), a positive number
#' when the model is in the snapshot, or `NA_real_` when it isn't.
#'
#' `input_tokens` is the *non-cached* prompt token count; cache tokens
#' are passed separately and priced on top. Anthropic cache tokens are
#' priced as published multiples of the base input rate (5-minute write
#' 1.25x, 1-hour write 2x, read 0.1x). For other providers there is no
#' separate write billing; `cache_read` is priced at the snapshot's
#' per-model `cache_read` rate, and the call returns `NA_real_` when
#' cache reads occurred but no such rate is bundled.
#'
#' @param model Character. Model id as sent to the provider.
#' @param provider Character. "anthropic", "openai", "moonshot", or
#'   "ollama".
#' @param input_tokens Integer. Non-cached prompt tokens.
#' @param output_tokens Integer. Completion tokens.
#' @param cache_write_5m,cache_write_1h Integer. Anthropic 5-minute /
#'   1-hour cache-write tokens.
#' @param cache_read Integer. Cache-hit tokens (Anthropic or
#'   OpenAI-compatible).
#' @return Numeric scalar (USD) or `NA_real_`.
#' @noRd
.cost_for <- function(model, provider, input_tokens, output_tokens,
                      cache_write_5m = 0, cache_write_1h = 0, cache_read = 0) {
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

    inp <- .num0(input_tokens)
    out <- .num0(output_tokens)
    w5 <- .num0(cache_write_5m)
    w1 <- .num0(cache_write_1h)
    rd <- .num0(cache_read)

    base <- inp * prices$input + out * prices$output

    if (identical(provider, "anthropic")) {
        return(base +
               w5 * prices$input * 1.25 +
               w1 * prices$input * 2 +
               rd * prices$input * 0.1)
    }

    # OpenAI / Moonshot: no cache-write charge; reads at the snapshot
    # cache_read rate. Unknown rate with reads present -> NA (honest
    # rather than silently billing reads at the full input rate).
    if (rd > 0) {
        if (is.null(prices$cache_read)) {
            return(NA_real_)
        }
        return(base + rd * prices$cache_read)
    }
    base
}

# Anthropic prompt-cache token counts from a usage list, as
# list(write_5m, write_1h, read); zeros when absent. Prefers the
# per-TTL split under `cache_creation`, else treats the flat
# `cache_creation_input_tokens` total as 5-minute writes. Uses `[[`
# throughout: `$` partial-matches, so `cache_creation` would wrongly
# resolve to `cache_creation_input_tokens` in the flat shape.
#' @noRd
.cache_tokens <- function(usage) {
    read <- .num0(usage[["cache_read_input_tokens"]])
    cc <- usage[["cache_creation"]]
    if (is.null(cc)) {
        w5 <- NULL
    } else {
        w5 <- cc[["ephemeral_5m_input_tokens"]]
    }
    if (is.null(cc)) {
        w1 <- NULL
    } else {
        w1 <- cc[["ephemeral_1h_input_tokens"]]
    }
    if (is.null(w5) && is.null(w1)) {
        w5 <- usage[["cache_creation_input_tokens"]]
        w1 <- 0
    }
    list(write_5m = .num0(w5), write_1h = .num0(w1), read = read)
}

# OpenAI-compatible cached prompt-token count. The nested
# `prompt_tokens_details` arrives as a named list under both the
# default and simplifyVector = FALSE JSON parses, so `[[` reads it
# safely either way (and avoids `$` partial matching).
#' @noRd
.openai_cached_tokens <- function(usage) {
    d <- usage[["prompt_tokens_details"]]
    if (is.null(d)) {
        return(0)
    }
    .num0(d[["cached_tokens"]])
}

#' Estimate the USD cost of one call's token usage
#'
#' Computes the offline cost estimate for a usage object, the same
#' value `chat()` and `agent()` attach as `usage$cost`. Reads whichever
#' shape the provider returned (Anthropic's `input_tokens` /
#' `output_tokens`, or the OpenAI-compatible `prompt_tokens` /
#' `completion_tokens`) and accounts for prompt caching: Anthropic
#' cache writes/reads via published multipliers, OpenAI / Moonshot
#' cache hits (`prompt_tokens_details$cached_tokens`) at the bundled
#' per-model `cache_read` rate.
#'
#' Costs come from the bundled price snapshot, so they are offline,
#' approximate, and may differ from current provider billing. See
#' [prices_snapshot_date()].
#'
#' @param model Character. Model id as sent to the provider.
#' @param provider Character. "anthropic", "openai", "moonshot", or
#'   "ollama".
#' @param usage A usage list as found in `chat()$usage` or
#'   `agent()$usage`.
#' @return Numeric scalar (USD), or `NA_real_` when `usage` is `NULL`,
#'   the model isn't in the snapshot, or cache reads can't be priced.
#' @export
#' @examples
#' \dontrun{
#' r <- chat("hi", model = "claude-sonnet-4-6", cache = "5m")
#' usage_cost("claude-sonnet-4-6", "anthropic", r$usage)
#' }
usage_cost <- function(model, provider, usage) {
    if (is.null(usage)) {
        return(NA_real_)
    }
    out_tokens <- usage[["output_tokens"]] %||% usage[["completion_tokens"]]

    if (identical(provider, "anthropic")) {
        ct <- .cache_tokens(usage)
        return(.cost_for(model, provider,
                         input_tokens = usage[["input_tokens"]],
                         output_tokens = out_tokens,
                         cache_write_5m = ct$write_5m,
                         cache_write_1h = ct$write_1h, cache_read = ct$read))
    }

    # OpenAI-compatible: prompt_tokens includes cached tokens, so split
    # them out and price the cached portion at the cache_read rate.
    prompt <- .num0(usage[["prompt_tokens"]] %||% usage[["input_tokens"]])
    cached <- .openai_cached_tokens(usage)
    uncached <- max(prompt - cached, 0)
    .cost_for(model, provider,
              input_tokens = uncached,
              output_tokens = out_tokens,
              cache_read = cached)
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

#' Bundled price-snapshot date
#'
#' `llm.api` estimates `usage$cost` from a model-price table baked into
#' the package at release time. This returns the date that bundled
#' table was generated.
#'
#' It does not contact the network, check for newer prices, or update
#' the installed package. Use the date to display staleness warnings
#' (see [prices_snapshot_stale()]) or to decide when the package
#' maintainer should regenerate the snapshot for a future release.
#'
#' The table is generated from BerriAI/litellm's
#' `model_prices_and_context_window.json`
#' (\url{https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json}).
#' Cost estimates are offline and approximate, and may differ from
#' current provider billing. Cached-input pricing follows each
#' provider's published model: OpenAI
#' (\url{https://platform.openai.com/docs/guides/prompt-caching}),
#' Moonshot (\url{https://www.kimi.com/help/kimi-api/api-pricing}), and
#' Anthropic
#' (\url{https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching}).
#'
#' @return Character scalar in `YYYY-MM-DD` format.
#' @seealso [prices_snapshot_stale()], [usage_cost()]
#' @export
#' @examples
#' prices_snapshot_date()
prices_snapshot_date <- function() {
    .PRICES_SNAPSHOT_DATE
}

#' Is the bundled price snapshot stale?
#'
#' Convenience wrapper over [prices_snapshot_date()] for staleness
#' alerts, so callers don't repeat the date arithmetic. Offline only;
#' it does not check the network for newer prices.
#'
#' @param max_age_days Numeric. Age threshold in days; default 90.
#' @return `TRUE` when the bundled snapshot is older than
#'   `max_age_days`, otherwise `FALSE`.
#' @seealso [prices_snapshot_date()]
#' @export
#' @examples
#' prices_snapshot_stale()
#' prices_snapshot_stale(max_age_days = 30)
prices_snapshot_stale <- function(max_age_days = 90) {
    age <- as.numeric(Sys.Date() - as.Date(.PRICES_SNAPSHOT_DATE))
    age > max_age_days
}

