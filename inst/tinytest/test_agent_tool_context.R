# agent() passes a read-only per-call context snapshot to a tool_handler
# that declares a `context` formal; two-argument handlers are unaffected.
# Offline: stubs llm.api:::.post_json, restoring it via finally.

ns <- asNamespace("llm.api")
orig_post_json <- get(".post_json", envir = ns, inherits = FALSE)
with_stubbed_post_json <- function(stub, expr) {
    assignInNamespace(".post_json", stub, ns = "llm.api")
    tryCatch(force(expr),
             finally = assignInNamespace(".post_json", orig_post_json, ns = "llm.api"))
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
