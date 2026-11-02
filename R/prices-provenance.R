#' Identify the bundled pricing data and calculation
#'
#' Offline MD5 fingerprints identify the serialized price table and the source
#' of the cost calculation bundled with this build. These are provenance
#' identifiers, not security checks or a claim that prices are current. The
#' calculation fingerprint includes provider overrides and cache multipliers.
#'
#' @return Named list with `table` and `calculation` fingerprints.
#' @seealso [prices_snapshot_date()], [usage_cost()]
#' @export
#' @examples
#' prices_snapshot_digest()
prices_snapshot_digest <- function() {
    .PRICES_SNAPSHOT_DIGEST
}

# The serialized bytes of an object without the stream header. A
# version-2 serialize() stream opens with "X\n" and three 4-byte
# integers: the format version, the R version that wrote the stream,
# and the minimum R version that can read it. The second changes with
# every R release, so a hash over the whole stream only matched on the R
# version that generated the snapshot. The payload after the 14-byte
# header is what identifies the table; data-raw/save-prices.R and the
# provenance test both hash that.
.serialize_payload <- function(stream) {
    stopifnot(is.raw(stream), length(stream) > 14L,
              identical(stream[1:2], as.raw(c(0x58, 0x0a))))
    stream[-(1:14)]
}
