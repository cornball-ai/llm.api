local({
    fingerprint <- llm.api::prices_snapshot_digest()
    expect_identical(names(fingerprint), c("table", "calculation"))
    expect_true(all(grepl("^md5:[a-f0-9]{32}$", unlist(fingerprint))))
    path <- tempfile()
    on.exit(unlink(path), add = TRUE)
    writeBin(serialize(get(".PRICES", asNamespace("llm.api")), NULL, version = 2L), path)
    expect_identical(fingerprint$table, paste0("md5:", unname(tools::md5sum(path))))
    # Source tests also catch stale calculation fingerprints after cost edits.
    if (file.exists("R/cost.R")) {
        expect_identical(fingerprint$calculation, paste0("md5:", unname(tools::md5sum("R/cost.R"))))
    }
})
