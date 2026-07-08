# Standard OpenAI Responses path (provider = "openai" + web_search).
# Offline: the shared SSE poster is stubbed. Asserts that web search routes
# openai through /v1/responses with a bearer key and the web_search tool,
# while a web-search-off openai call stays on chat-completions.

ns <- asNamespace("llm.api")

`%||%` <- function(x, y) if (is.null(x)) y else x
tool_types <- function(tools) {
    if (length(tools) == 0L) {
        character(0)
    } else {
        vapply(tools, function(t) t$type %||% "?", character(1))
    }
}

with_stubbed <- function(name, stub, expr) {
    orig <- get(name, envir = ns, inherits = FALSE)
    assignInNamespace(name, stub, ns = "llm.api")
    tryCatch(force(expr),
             finally = assignInNamespace(name, orig, ns = "llm.api"))
}

# Captures the URL/body/headers handed to the shared SSE poster and returns a
# minimal Responses payload (a message plus one search and one citation).
capture_responses <- function(target) {
    function(url, body, headers) {
        target$url <- url
        target$body <- body
        target$headers <- headers
        list(output = list(
            list(type = "web_search_call", status = "completed",
                 action = list(type = "search", query = "news today",
                               queries = list("news today"))),
            list(type = "message", content = list(list(
                type = "output_text", text = "ok",
                annotations = list(list(type = "url_citation",
                                        url = "https://example.com",
                                        title = "Example")))))),
            usage = list(input_tokens = 5L, output_tokens = 2L,
                         input_tokens_details = list(cached_tokens = 0L)))
    }
}

old_opts <- options(llm.api_base = NULL, llm.api_key = NULL, llm.api.api_base = NULL, llm.api.api_key = NULL)
on.exit(options(old_opts), add = TRUE)
old_key <- Sys.getenv("OPENAI_API_KEY", unset = NA_character_)
on.exit({
    if (is.na(old_key)) {
        Sys.unsetenv("OPENAI_API_KEY")
    } else {
        Sys.setenv(OPENAI_API_KEY = old_key)
    }
}, add = TRUE)
Sys.setenv(OPENAI_API_KEY = "sk-test-openai")

# openai is in the web-search provider set.
expect_true("openai" %in% ns$.web_search_providers())

# Body builder: keeps max_output_tokens (the public endpoint honors caps,
# unlike /codex/responses), injects the web_search tool, and consumes the flag.
mk_user <- function() list(list(role = "user", content = "hi"))
b <- ns$.openai_responses_body(mk_user(), list(), "sys", "gpt-5.4-mini",
                               web_search = TRUE, max_tokens = 99L)
expect_true("web_search" %in% tool_types(b$tools))
expect_null(b$web_search)
expect_equal(b$max_output_tokens, 99L)
expect_null(b$max_tokens)
expect_equal(b$instructions, "sys")
expect_true(isFALSE(b$store))

boff <- ns$.openai_responses_body(mk_user(), list(), "sys", "gpt-5.4-mini")
expect_false("web_search" %in% tool_types(boff$tools))

# chat(): web_search routes to /v1/responses with a bearer key; the response
# carries searches + citations.
local({
    cap <- new.env()
    res <- with_stubbed(".openai_codex_post_sse", capture_responses(cap), {
        llm.api::chat("what's new?", provider = "openai", model = "gpt-5.4-mini",
                      web_search = TRUE)
    })
    expect_equal(cap$url, "https://api.openai.com/v1/responses")
    expect_equal(cap$headers[["Authorization"]], "Bearer sk-test-openai")
    expect_true("web_search" %in% tool_types(cap$body$tools))
    expect_equal(length(res$searches), 1L)
    expect_equal(res$searches[[1]]$query, "news today")
    expect_equal(length(res$citations), 1L)
    expect_equal(res$citations[[1]]$url, "https://example.com")
})

# chat() without web_search stays on chat-completions (Responses poster
# untouched); stub it to fail if hit.
local({
    boom <- function(url, body, headers) stop("should not route to Responses")
    hit <- FALSE
    res <- with_stubbed(".openai_codex_post_sse", boom, {
        with_stubbed(".chat_openai_compatible",
                     function(body, config, stream) {
                         list(content = "cc", usage = NULL)
                     }, {
            llm.api::chat("hi", provider = "openai", model = "gpt-5.4-mini")
        })
    })
    expect_equal(res$content, "cc")
})

# agent(): web_search drives the Responses wire (flat tools, /v1/responses).
local({
    cap <- new.env()
    res <- with_stubbed(".openai_codex_post_sse", capture_responses(cap), {
        llm.api::agent("go", provider = "openai", model = "gpt-5.4-mini",
                       web_search = TRUE, verbose = FALSE)
    })
    expect_equal(cap$url, "https://api.openai.com/v1/responses")
    expect_true("web_search" %in% tool_types(cap$body$tools))
    expect_equal(length(res$searches), 1L)
    expect_equal(length(res$citations), 1L)
})

# agent(): a user tool is converted to the flat Responses shape (name at the
# top level, not nested under `function`).
local({
    cap <- new.env()
    tools <- list(list(name = "noop", description = "d",
                       input_schema = list(type = "object")))
    with_stubbed(".openai_codex_post_sse", capture_responses(cap), {
        llm.api::agent("go", tools = tools,
                       tool_handler = function(n, a) "x",
                       provider = "openai", model = "gpt-5.4-mini",
                       web_search = TRUE, verbose = FALSE)
    })
    user_tool <- Filter(function(t) identical(t$type, "function"), cap$body$tools)
    expect_equal(length(user_tool), 1L)
    expect_equal(user_tool[[1]]$name, "noop")
    expect_null(user_tool[[1]]$`function`)
})
