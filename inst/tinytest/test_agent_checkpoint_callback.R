# Safe between-turn history replacement and prompt-free continuation.

ns <- asNamespace("llm.api")
orig_sse <- get(".anthropic_post_sse", envir = ns, inherits = FALSE)

with_stubbed_sse <- function(stub, expr) {
    assignInNamespace(".anthropic_post_sse", stub, ns = "llm.api")
    tryCatch(force(expr),
             finally = assignInNamespace(".anthropic_post_sse", orig_sse,
            ns = "llm.api"))
}

tool <- list(list(name = "echo", description = "echo",
                  input_schema = list(type = "object")))

# The checkpoint runs once after the complete tool batch and its returned
# provider-native history is the input to the next request.
bodies <- list()
calls <- 0L
stub <- function(url, body, headers, on_delta = NULL) {
    calls <<- calls + 1L
    bodies[[calls]] <<- body
    if (calls == 1L) {
        list(content = list(
                            list(type = "text", text = "using tool"),
                            list(type = "tool_use", id = "tu_1", name = "echo",
                                 input = list(x = 1L))
            ), usage = list(input_tokens = 10L, output_tokens = 5L))
    } else {
        list(content = list(list(type = "text", text = "done")),
             usage = list(input_tokens = 12L, output_tokens = 3L))
    }
}

seen_context <- NULL
snapshots <- list()
result <- with_stubbed_sse(stub, llm.api::agent(
        prompt = "original",
        tools = tool,
        tool_handler = function(name, args) "ok",
        provider = "anthropic",
        model = "test-model",
        verbose = FALSE,
        history_callback = function(history) {
    snapshots[[length(snapshots) + 1L]] <<- history
},
        checkpoint_callback = function(history, context) {
    seen_context <<- context
    history[[1L]]$content <- "compacted"
    list(history = history)
}
    ))

expect_equal(calls, 2L)
expect_equal(bodies[[2L]]$messages[[1L]]$content, "compacted")
expect_equal(seen_context$agent_turn, 1L)
expect_equal(seen_context$tool_call_count, 1L)
expect_equal(seen_context$provider, "anthropic")
expect_equal(seen_context$model, "test-model")
expect_equal(length(snapshots), 4L)
expect_equal(result$history[[1L]]$content, "compacted")

# NULL prompt means continue the supplied history without adding a synthetic
# user message. This is the recovery path after a host compacts an overflowed
# request that already contains its user/tool-result trigger.
resume_body <- NULL
resume_stub <- function(url, body, headers, on_delta = NULL) {
    resume_body <<- body
    list(content = list(list(type = "text", text = "resumed")),
         usage = list(input_tokens = 4L, output_tokens = 2L))
}
resume <- with_stubbed_sse(resume_stub, llm.api::agent(prompt = NULL,
        history = list(list(role = "user", content = "existing")),
        provider = "anthropic", model = "test-model", verbose = FALSE))
expect_equal(length(resume_body$messages), 1L)
expect_equal(resume_body$messages[[1L]]$content, "existing")
expect_equal(length(resume$history), 2L)

expect_error(llm.api::agent(prompt = NULL, history = list(),
                            provider = "anthropic", verbose = FALSE),
             pattern = "requires non-empty")
expect_error(llm.api::agent(prompt = "x", checkpoint_callback = 1,
                            provider = "anthropic", verbose = FALSE),
             pattern = "must be a function")

# A malformed control return fails loudly instead of silently running the next
# expensive model request on an unverified history.
bad_calls <- 0L
bad_stub <- function(url, body, headers, on_delta = NULL) {
    bad_calls <<- bad_calls + 1L
    list(content = list(list(type = "tool_use", id = "tu_bad", name = "echo",
                             input = list())),
         usage = list(input_tokens = 1L, output_tokens = 1L))
}
expect_error(with_stubbed_sse(bad_stub, llm.api::agent(
            prompt = "go", tools = tool,
            tool_handler = function(name, args) "ok",
            provider = "anthropic", model = "test-model", verbose = FALSE,
            checkpoint_callback = function(history, context) list(no_history = TRUE)
        )), pattern = "must return NULL")
expect_equal(bad_calls, 1L)
