# agent() passes an immutable per-call context to a tool_handler that
# declares a `context` formal; two-argument handlers are unaffected.
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
