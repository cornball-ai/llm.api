# Verifies that agent() invokes the history_callback at every history
# mutation point: after each assistant message lands AND after each
# tool result is appended. The point is that a caller can use the
# callback to snapshot intermediate state, so an interrupt mid-turn
# doesn't lose completed tool calls.
#
# Stubs llm.api:::.post_json so the test is offline.

ns <- asNamespace("llm.api")
orig_post_json <- get(".post_json", envir = ns, inherits = FALSE)

# Two-stage stub: first call returns an assistant message with two
# tool_use blocks; second call returns text-only (end of turn).
call_count <- 0L
stub <- function(url, body, headers) {
    call_count <<- call_count + 1L
    if (call_count == 1L) {
        list(
             content = list(
                            list(type = "text", text = "running two tools"),
                            list(type = "tool_use", id = "tu_1",
                                 name = "echo", input = list(x = 1L)),
                            list(type = "tool_use", id = "tu_2",
                                 name = "echo", input = list(x = 2L))
            ),
             usage = list(input_tokens = 10L, output_tokens = 5L)
        )
    } else {
        list(
             content = list(
                            list(type = "text", text = "all done")
            ),
             usage = list(input_tokens = 12L, output_tokens = 3L)
        )
    }
}

# --- Test 1: callback fires at all four expected points -------------
assignInNamespace(".post_json", stub, ns = "llm.api")

snapshots <- list()
record <- function(messages) {
    snapshots[[length(snapshots) + 1L]] <<- list(
                                                 length = length(messages),
                                                 last_role = messages[[length(messages)]]$role,
                                                 last_content_n =
                                                     if (is.list(messages[[length(messages)]]$content)) {
                                                         length(messages[[length(messages)]]$content)
                                                     } else {
                                                         NA_integer_
                                                     }
    )
}

result <- llm.api::agent(
                         prompt = "go",
                         tools = list(list(name = "echo", description = "d",
                                           input_schema = list(type = "object"))),
                         tool_handler = function(name, args) sprintf("res-%s", args$x),
                         model = "claude-test",
                         provider = "anthropic",
                         verbose = FALSE,
                         history_callback = record
)

assignInNamespace(".post_json", orig_post_json, ns = "llm.api")

# Final result smoke-checks.
expect_equal(result$content, "all done")
expect_equal(call_count, 2L)

# Callback should have fired exactly four times:
#   1. After first assistant message (with 2 tool_uses)
#   2. After first tool_result block appended to a new user message
#   3. After second tool_result block extended that same user message
#   4. After the final text-only assistant message
expect_equal(length(snapshots), 4L)

# Fire 1: assistant message just landed. Messages = [user, assistant].
expect_equal(snapshots[[1L]]$length, 2L)
expect_equal(snapshots[[1L]]$last_role, "assistant")

# Fire 2: first tool_result added. Messages = [user, assistant, user].
# That user message has one tool_result block.
expect_equal(snapshots[[2L]]$length, 3L)
expect_equal(snapshots[[2L]]$last_role, "user")
expect_equal(snapshots[[2L]]$last_content_n, 1L)

# Fire 3: second tool_result EXTENDS the existing user message rather
# than starting a new one. Messages length stays at 3, content grows.
expect_equal(snapshots[[3L]]$length, 3L)
expect_equal(snapshots[[3L]]$last_role, "user")
expect_equal(snapshots[[3L]]$last_content_n, 2L)

# Fire 4: final assistant message lands.
expect_equal(snapshots[[4L]]$length, 4L)
expect_equal(snapshots[[4L]]$last_role, "assistant")

# --- Test 2: callback errors are swallowed, turn still completes ----
call_count <- 0L
assignInNamespace(".post_json", stub, ns = "llm.api")

result2 <- llm.api::agent(
                          prompt = "go",
                          tools = list(list(name = "echo", description = "d",
                                            input_schema = list(type = "object"))),
                          tool_handler = function(name, args) sprintf("res-%s", args$x),
                          model = "claude-test",
                          provider = "anthropic",
                          verbose = FALSE,
                          history_callback = function(messages) {
                              stop("simulated telemetry failure")
                          }
)

assignInNamespace(".post_json", orig_post_json, ns = "llm.api")

expect_equal(result2$content, "all done")
expect_equal(length(result2$history), 4L)
