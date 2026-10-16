local({
    ns <- asNamespace("llm.api")
    original <- ns$.models_get
    opts <- options(llm.api_base = NULL, llm.api.api_base = NULL,
                    llm.api_key = "fixture-key")
    on.exit({
        options(opts)
        assignInNamespace(".models_get", original, "llm.api")
    }, add = TRUE)
    seen <- list()
    assignInNamespace(".models_get", function(url, headers, timeout) {
        seen[[length(seen) + 1L]] <<- list(url = url, headers = headers,
                                          timeout = timeout)
        if (grepl("/api/tags$", url)) {
            return(list(models = list(list(name = "local-small"), list(name = "local-large"))))
        }
        if (grepl("after_id=", url)) {
            return(list(data = list(list(id = "claude-second")), has_more = FALSE))
        }
        list(data = list(list(id = "model-b"), list(id = "model-a")),
             has_more = grepl("limit=1000", url), last_id = "cursor/one")
    }, "llm.api")
    models <- llm.api::list_models("openai", timeout = 3)
    expect_equal(as.vector(models), c("model-a", "model-b"))
    expect_equal(attr(models, "source"), "provider")
    expect_equal(seen[[1]]$url, "https://api.openai.com/v1/models")
    expect_equal(seen[[1]]$headers$Authorization, "Bearer fixture-key")
    expect_equal(seen[[1]]$timeout, 3)
    models <- llm.api::list_models("anthropic")
    expect_equal(length(models), 3L)
    expect_equal(seen[[2]]$headers[["x-api-key"]], "fixture-key")
    expect_equal(seen[[2]]$headers[["anthropic-version"]], "2023-06-01")
    expect_true(grepl("after_id=cursor%2Fone", seen[[3]]$url, fixed = TRUE))
    models <- llm.api::list_models("openai_compatible", base_url = "https://example.invalid/v1/")
    expect_equal(seen[[4]]$url, "https://example.invalid/v1/models")
    models <- llm.api::list_models("ollama", base_url = "http://localhost:12345")
    expect_equal(as.vector(models), c("local-large", "local-small"))
    expect_equal(seen[[5]]$url, "http://localhost:12345/api/tags")
    expect_error(llm.api::list_models("anthropic_claude"), "No model catalog")
    path <- tempfile(fileext = ".json")
    on.exit(unlink(path), add = TRUE)
    jsonlite::write_json(list(models = list(
        list(slug = "gpt-visible", visibility = "list"),
        list(slug = "gpt-hidden", visibility = "hide"))), path, auto_unbox = TRUE)
    cached <- llm.api::list_models("openai_codex", codex_cache = path)
    expect_equal(as.vector(cached), "gpt-visible")
    expect_equal(attr(cached, "source"), "Codex cache")
    expect_equal(length(seen), 5L)
    assignInNamespace(".models_get", function(...) list(error = "bad"), "llm.api")
    expect_error(llm.api::list_models("openai"), "Invalid provider model catalog")
})
