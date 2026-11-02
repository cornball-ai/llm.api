# Regenerate provenance from the already loaded table. This step is offline;
# run after changing cost.R as well as after refreshing the price table.
# With `.PRICES` and `.PRICES_SNAPSHOT_DATE` in the calling environment:
#
#   r -e 'e <- new.env(); load("R/sysdata.rda", envir = e);
#         sys.source("data-raw/save-prices.R", envir = e)'
#
# The table digest is the md5 of the serialized payload with the stream
# header stripped by .serialize_payload() from R/prices-provenance.R
# (sourced here so the script does not need the installed package). The
# header carries the R version that wrote it, so a header-inclusive hash
# only matched on that one R version. inst/tinytest/test_prices_provenance.R
# recomputes the same digest from the loaded table.
local({
    source("R/prices-provenance.R", local = TRUE)
    tmp <- tempfile()
    on.exit(unlink(tmp), add = TRUE)
    writeBin(.serialize_payload(serialize(.PRICES, NULL, version = 2L)), tmp)
    .PRICES_SNAPSHOT_DIGEST <- list(
        table = paste0("md5:", unname(tools::md5sum(tmp))),
        calculation = paste0("md5:", unname(tools::md5sum("R/cost.R"))))
    save(.PRICES, .PRICES_SNAPSHOT_DATE, .PRICES_SNAPSHOT_DIGEST,
        file = "R/sysdata.rda", compress = "xz")
})
