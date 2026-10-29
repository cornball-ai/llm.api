# Regenerate provenance from the already loaded table. This step is offline;
# run after changing cost.R as well as after refreshing the price table.
local({
    tmp <- tempfile()
    on.exit(unlink(tmp), add = TRUE)
    writeBin(serialize(.PRICES, NULL, version = 2L), tmp)
    .PRICES_SNAPSHOT_DIGEST <- list(
        table = paste0("md5:", unname(tools::md5sum(tmp))),
        calculation = paste0("md5:", unname(tools::md5sum("R/cost.R"))))
    save(.PRICES, .PRICES_SNAPSHOT_DATE, .PRICES_SNAPSHOT_DIGEST,
        file = "R/sysdata.rda", compress = "xz")
})
