# Moonshot $web_search tests. Offline: the JSON poster is stubbed to simulate
# the builtin-search round-trip (a $web_search tool call, then a final answer).

ns <- asNamespace("llm.api")

`%||%` <- function(x, y) if (is.null(x)) y else x

with_stubbed <- function(name, stub, expr) {
    orig <- get(name, envir = ns, inherits = FALSE)
    assignInNamespace(name, stub, ns = "llm.api")
    tryCatch(force(expr),
             finally = assignInNamespace(name, orig, ns = "llm.api"))
}

old_opts <- options(llm.api.api_base = NULL, llm.api.api_key = NULL)
on.exit(options(old_opts), add = TRUE)
old_key <- Sys.getenv("MOONSHOT_API_KEY", unset = NA_character_)
on.exit({
    if (is.na(old_key)) {
        Sys.unsetenv("MOONSHOT_API_KEY")
    } else {
        Sys.setenv(MOONSHOT_API_KEY = old_key)
    }
}, add = TRUE)
Sys.setenv(MOONSHOT_API_KEY = "sk-test-moonshot")

# moonshot is in the web-search provider set.
expect_true("moonshot" %in% ns$.web_search_providers())

# tool builder: off -> NULL; on -> the $web_search builtin.
expect_null(ns$.moonshot_web_search_tool(FALSE))
expect_null(ns$.moonshot_web_search_tool(NULL))
wt <- ns$.moonshot_web_search_tool(TRUE)
expect_equal(wt$type, "builtin_function")
expect_equal(wt$`function`$name, "$web_search")

# unsupported options warn once per session. Bind the state env locally first:
# `ns$.moonshot_state$x <- NULL` would try to rebind the locked namespace
# binding, but mutating a local handle to the same env is fine.
moonshot_state <- ns$.moonshot_state
moonshot_state$warned_web_search_opts <- NULL
expect_warning(ns$.moonshot_web_search_tool(list(allowed_domains = "x")),
               "ignores")

# echo coercion: a JSON *string*, not a "json"-classed object (else jsonlite
# would re-embed it as a raw object in the next request body).
echo <- ns$.moonshot_web_search_echo(list(search_result = list(search_id = "s1")))
expect_true(is.character(echo))
expect_false(inherits(echo, "json"))
expect_equal(echo, "{\"search_result\":{\"search_id\":\"s1\"}}")

# A stubbed two-step round-trip: first response asks for a $web_search; second
# (after the echo) returns the final answer. Records the messages it was sent.
mk_poster <- function(target) {
    target$calls <- 0L
    function(url, body, headers) {
        target$calls <- target$calls + 1L
        target$last_messages <- body$messages
        target$last_tools <- body$tools
        if (target$calls == 1L) {
            list(choices = list(list(
                finish_reason = "tool_calls",
                message = list(role = "assistant", content = "",
                    tool_calls = list(list(
                        id = "t-web_search-1", type = "builtin_function",
                        `function` = list(name = "$web_search",
                            arguments = "{\"search_result\":{\"search_id\":\"s1\"}}"))))
            )), usage = list(prompt_tokens = 1L, completion_tokens = 1L))
        } else {
            list(choices = list(list(
                finish_reason = "stop",
                message = list(role = "assistant",
                    content = "Seattle won. (source: example.com)")
            )), usage = list(prompt_tokens = 5L, completion_tokens = 3L))
        }
    }
}

# chat(): drives the echo loop internally and returns the final text + a search
# record (query = NA, since Moonshot doesn't expose it). Two HTTP calls.
local({
    cap <- new.env()
    res <- with_stubbed(".post_json", mk_poster(cap), {
        llm.api::chat("news?", provider = "moonshot", model = "kimi-k2.5",
                      web_search = TRUE)
    })
    expect_equal(cap$calls, 2L)
    expect_equal(res$content, "Seattle won. (source: example.com)")
    expect_equal(length(res$searches), 1L)
    expect_true(is.na(res$searches[[1]]$query))
    expect_equal(length(res$citations), 0L)
    # The builtin tool was sent on each request.
    expect_equal(cap$last_tools[[1]]$`function`$name, "$web_search")
    # The echoed tool result carries the call's arguments verbatim.
    echoed <- cap$last_messages[[length(cap$last_messages)]]
    expect_equal(echoed$role, "tool")
    expect_equal(echoed$name, "$web_search")
    expect_equal(echoed$content, "{\"search_result\":{\"search_id\":\"s1\"}}")
})

# agent(): a user tool plus web search. The $web_search call is intercepted
# (echoed, not routed to tool_handler); the user tool still runs.
local({
    cap <- new.env()
    cap$calls <- 0L
    handler_hits <- new.env()
    handler_hits$names <- character(0)
    handler <- function(name, args) {
        handler_hits$names <- c(handler_hits$names, name)
        "user-result"
    }
    poster <- function(url, body, headers) {
        cap$calls <- cap$calls + 1L
        if (cap$calls == 1L) {
            list(choices = list(list(finish_reason = "tool_calls",
                message = list(role = "assistant", content = "",
                    tool_calls = list(list(id = "t-web_search-1",
                        type = "builtin_function",
                        `function` = list(name = "$web_search",
                            arguments = "{\"search_result\":{\"search_id\":\"s1\"}}")))))),
                usage = list(prompt_tokens = 1L, completion_tokens = 1L))
        } else {
            list(choices = list(list(finish_reason = "stop",
                message = list(role = "assistant", content = "done"))),
                usage = list(prompt_tokens = 2L, completion_tokens = 1L))
        }
    }
    res <- with_stubbed(".post_json", poster, {
        llm.api::agent("go", provider = "moonshot", model = "kimi-k2.5",
                       web_search = TRUE, verbose = FALSE, max_turns = 5)
    })
    expect_equal(res$content, "done")
    expect_equal(length(res$searches), 1L)
    # tool_handler never saw $web_search.
    expect_false("$web_search" %in% handler_hits$names)
})

# guard still fires for a provider with no web search wired.
expect_warning(
    llm.api::chat("hi", provider = "ollama", model = "x", web_search = TRUE),
    "not yet supported")
