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
