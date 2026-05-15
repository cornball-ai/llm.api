# Snapshot per-token prices into R/sysdata.rda so cost lookup is
# offline and CRAN-safe. Source is the same upstream that the ellmer
# package uses:
#
#   https://github.com/BerriAI/litellm
#
# Run this manually when you want a fresh snapshot:
#
#   r -e 'source("data-raw/prices.R")'
#
# Output is `.PRICES`, a flat named list keyed by the litellm model
# id (e.g. "gpt-4o", "claude-sonnet-4-6", "moonshot/kimi-k2.5"), each
# entry list(input = <USD/token>, output = <USD/token>, provider =
# <litellm_provider>). Entries with zero input and zero output cost
# (sample_spec, free local models, partial records) are dropped.

URL <- "https://raw.githubusercontent.com/BerriAI/litellm/refs/heads/main/model_prices_and_context_window.json"

tmp <- tempfile(fileext = ".json")
on.exit(unlink(tmp), add = TRUE)
utils::download.file(URL, tmp, mode = "wb", quiet = TRUE)

raw <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)
raw[["sample_spec"]] <- NULL

.PRICES <- list()
for (key in names(raw)) {
  rec <- raw[[key]]
  inp <- rec$input_cost_per_token
  out <- rec$output_cost_per_token
  if (is.null(inp) && is.null(out)) next
  inp <- if (is.null(inp)) 0 else as.numeric(inp)
  out <- if (is.null(out)) 0 else as.numeric(out)
  if (inp == 0 && out == 0) next
  .PRICES[[key]] <- list(
    input = inp,
    output = out,
    provider = rec$litellm_provider %||% NA_character_
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# Stamp the snapshot date so cran-comments / NEWS can cite it.
.PRICES_SNAPSHOT_DATE <- format(Sys.Date())

message(sprintf("Snapshot: %d models, %s", length(.PRICES), .PRICES_SNAPSHOT_DATE))

save(.PRICES, .PRICES_SNAPSHOT_DATE,
     file = "R/sysdata.rda",
     compress = "xz")
