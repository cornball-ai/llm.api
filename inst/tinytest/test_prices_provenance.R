# Same computation as data-raw/save-prices.R: md5 of the serialized
# payload, header stripped by the package helper.
table_digest <- function(table) {
    path <- tempfile()
    on.exit(unlink(path), add = TRUE)
    writeBin(llm.api:::.serialize_payload(serialize(table, NULL, version = 2L)),
             path)
    paste0("md5:", unname(tools::md5sum(path)))
}

local({
    fingerprint <- llm.api::prices_snapshot_digest()
    expect_identical(names(fingerprint), c("table", "calculation"))
    expect_true(all(grepl("^md5:[a-f0-9]{32}$", unlist(fingerprint))))
    # The bundled table digest matches one computed from the loaded table,
    # so a refreshed table without a re-run of data-raw/save-prices.R fails
    # here.
    expect_identical(fingerprint$table,
                     table_digest(get(".PRICES", asNamespace("llm.api"))))
    # Source tests also catch stale calculation fingerprints after cost edits.
    if (file.exists("R/cost.R")) {
        expect_identical(fingerprint$calculation, paste0("md5:", unname(tools::md5sum("R/cost.R"))))
    }
})

# The digest ignores the serialize stream header. Bytes 7 to 10 of a
# version-2 stream hold the R version that wrote it, so a hash over the
# whole stream matched only on the R version that generated the snapshot
# (the CI runner moved to a newer R and the check above failed).
local({
    stream <- serialize(list(input = 1e-6, output = 2e-6), NULL, version = 2L)
    expect_identical(stream[1:2], as.raw(c(0x58, 0x0a)))  # "X\n"
    other <- stream
    other[7:10] <- as.raw(c(0x00, 0x04, 0x09, 0x09))  # as if written by R 4.9.9
    expect_false(identical(stream, other))
    expect_identical(llm.api:::.serialize_payload(stream),
                     llm.api:::.serialize_payload(other))
    expect_identical(llm.api:::.serialize_payload(stream), stream[-(1:14)])
})
