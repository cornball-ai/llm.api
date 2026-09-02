# agent() passes a read-only per-call context snapshot to a tool_handler
# that declares a `context` formal; two-argument handlers are unaffected.
# Offline: stubs llm.api:::.post_json, restoring it via finally.

ns <- asNamespace("llm.api")
orig_post_json <- get(".post_json", envir = ns, inherits = FALSE)
orig_post_sse <- get(".anthropic_post_sse", envir = ns, inherits = FALSE)
# The Anthropic agent path streams (0.1.9.8), so a stub on the plain
# POST alone is never reached there: install it on both transports.
with_stubbed_post_json <- function(stub, expr) {
    sse <- function(url, body, headers, on_delta = NULL) stub(url, body, headers)
    assignInNamespace(".post_json", stub, ns = "llm.api")
    assignInNamespace(".anthropic_post_sse", sse, ns = "llm.api")
    tryCatch(force(expr),
             finally = {
                 assignInNamespace(".post_json", orig_post_json, ns = "llm.api")
                 assignInNamespace(".anthropic_post_sse", orig_post_sse, ns = "llm.api")
             })
}

# First response: assistant text + two tool_use blocks. Second: end turn.
call_count <- 0L
stub <- function(url, body, headers) {
    call_count <<- call_count + 1L
    if (call_count == 1L) {
        list(content = list(
                            list(type = "text", text = "running two tools"),
                            list(type = "tool_use", id = "tu_1", name = "echo",
                                 input = list(x = 1L)),
                            list(type = "tool_use", id = "tu_2", name = "echo",
                                 input = list(x = 2L))),
             usage = list(input_tokens = 10L, output_tokens = 5L))
    } else {
        list(content = list(list(type = "text", text = "done")),
             usage = list(input_tokens = 1L, output_tokens = 1L))
    }
}

echo_tools <- list(list(name = "echo", description = "d",
                        input_schema = list(type = "object")))

# --- context-aware handler receives the per-call context ---
seen <- list()
ctx_handler <- function(name, args, context = NULL) {
    seen[[length(seen) + 1L]] <<- context
    sprintf("res-%s", args$x)
}
res <- with_stubbed_post_json(stub, llm.api::agent(
                                                   prompt = "go", tools = echo_tools,
                                                   tool_handler = ctx_handler,
                                                   model = "claude-test", provider = "anthropic",
                                                   verbose = FALSE))

expect_equal(res$content, "done")
expect_equal(length(seen), 2L)
# Both calls share the same turn, assistant text, and call_count; the
# call_index advances 1 -> 2.
expect_equal(seen[[1L]]$assistant_text, "running two tools")
expect_equal(seen[[1L]]$agent_turn, 1L)
expect_equal(seen[[1L]]$call_index, 1L)
expect_equal(seen[[1L]]$call_count, 2L)
expect_equal(seen[[1L]]$provider, "anthropic")
expect_equal(seen[[2L]]$call_index, 2L)
expect_equal(seen[[2L]]$assistant_text, "running two tools")

# --- two-argument handler is called unchanged (no error) ---
call_count <- 0L
res2 <- with_stubbed_post_json(stub, llm.api::agent(
                                                    prompt = "go", tools = echo_tools,
                                                    tool_handler = function(name, args) sprintf("r-%s", args$x),
                                                    model = "claude-test", provider = "anthropic",
                                                    verbose = FALSE))
expect_equal(res2$content, "done")

# --- context arrives by name, even declared after `...` ---
# Positional passing would land context inside `...` and leave it NULL.
call_count <- 0L
dots_seen <- list()
dots_handler <- function(name, args, ..., context = NULL) {
    dots_seen[[length(dots_seen) + 1L]] <<- context
    sprintf("res-%s", args$x)
}
res3 <- with_stubbed_post_json(stub, llm.api::agent(
                                                    prompt = "go", tools = echo_tools,
                                                    tool_handler = dots_handler,
                                                    model = "claude-test", provider = "anthropic",
                                                    verbose = FALSE))
expect_equal(res3$content, "done")
expect_equal(length(dots_seen), 2L)
expect_false(is.null(dots_seen[[1L]]))
expect_equal(dots_seen[[1L]]$assistant_text, "running two tools")
expect_equal(dots_seen[[1L]]$call_count, 2L)

# --- call_index/call_count exclude internally-consumed calls ---
# A Moonshot batch with a server-side $web_search call plus two echo
# calls: only the echoes reach the handler, indexed 1..2 of 2 (not 3).
moon_count <- 0L
moon_stub <- function(url, body, headers) {
    moon_count <<- moon_count + 1L
    if (moon_count == 1L) {
        list(choices = list(list(message = list(
                                               role = "assistant", content = "search then two tools",
                                               tool_calls = list(
                                                                 list(id = "ws_1", type = "function", `function` = list(
                                                                                    name = "$web_search", arguments = "{\"search_id\":\"s1\"}")),
                                                                 list(id = "call_1", type = "function", `function` = list(
                                                                                    name = "echo", arguments = "{\"x\":1}")),
                                                                 list(id = "call_2", type = "function", `function` = list(
                                                                                    name = "echo", arguments = "{\"x\":2}"))),
                                               finish_reason = "tool_calls")),
                            usage = list(prompt_tokens = 10L, completion_tokens = 5L)))
    } else {
        list(choices = list(list(message = list(role = "assistant", content = "done"),
                                 finish_reason = "stop")),
             usage = list(prompt_tokens = 1L, completion_tokens = 1L))
    }
}
moon_seen <- list()
moon_handler <- function(name, args, context = NULL) {
    moon_seen[[length(moon_seen) + 1L]] <<- context
    sprintf("m-%s", args$x)
}
moon_res <- with_stubbed_post_json(moon_stub, llm.api::agent(
                                                            prompt = "go",
                                                            tools = list(list(type = "function",
                                                                              `function` = list(name = "echo", description = "d"))),
                                                            tool_handler = moon_handler,
                                                            model = "kimi-test", provider = "moonshot",
                                                            web_search = TRUE, verbose = FALSE))
expect_equal(moon_res$content, "done")
expect_equal(length(moon_seen), 2L)
expect_equal(moon_seen[[1L]]$call_index, 1L)
expect_equal(moon_seen[[1L]]$call_count, 2L)
expect_equal(moon_seen[[2L]]$call_index, 2L)
expect_equal(moon_seen[[2L]]$call_count, 2L)
expect_equal(moon_seen[[1L]]$provider, "moonshot")

# --- regression: anthropic_claude (subscription OAuth) drives the anthropic
# wire, so tool results are appended and the messages array stays valid on the
# turn after a tool call. Pre-fix, .append_tool_result() didn't match the
# literal "anthropic_claude", returned NULL, and corrupted messages (a 400). ---
local({
    old <- Sys.getenv("ANTHROPIC_CLAUDE_ACCESS_TOKEN", unset = NA)
    Sys.setenv(ANTHROPIC_CLAUDE_ACCESS_TOKEN = "test-token")
    on.exit(if (is.na(old)) Sys.unsetenv("ANTHROPIC_CLAUDE_ACCESS_TOKEN")
            else Sys.setenv(ANTHROPIC_CLAUDE_ACCESS_TOKEN = old), add = TRUE)

    captured <- NULL
    ac_stub <- function(url, body, headers) {
        if (length(body$messages) <= 1L) {
            list(content = list(list(type = "tool_use", id = "t1",
                                     name = "echo", input = list(x = 1L))),
                 usage = list(input_tokens = 5L, output_tokens = 2L))
        } else {
            captured <<- body$messages
            list(content = list(list(type = "text", text = "ok")),
                 usage = list(input_tokens = 1L, output_tokens = 1L))
        }
    }
    ac_res <- with_stubbed_post_json(ac_stub, llm.api::agent(
        prompt = "go", tools = echo_tools,
        tool_handler = function(name, args) "echoed",
        model = "claude-test", provider = "anthropic_claude",
        verbose = FALSE))

    expect_equal(ac_res$content, "ok")
    # Post-tool-result request: messages is a valid array carrying the
    # tool_result, not NULL.
    expect_false(is.null(captured))
    expect_true(length(captured) >= 3L)
    expect_identical(captured[[length(captured)]]$content[[1]]$type,
                     "tool_result")
})
