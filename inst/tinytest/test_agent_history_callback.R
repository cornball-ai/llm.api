# Verifies that agent() invokes the history_callback at every history
# mutation point: after each assistant message lands AND after each
# tool result is appended. The point is that a caller can use the
# callback to snapshot intermediate state, so an interrupt mid-turn
# doesn't lose completed tool calls.
#
# Stubs llm.api:::.post_json so the test is offline. Each stubbed
# section restores the original via tryCatch(..., finally = ...) so
# an error inside agent() can't leak the stub into later tests.

ns <- asNamespace("llm.api")
orig_post_json <- get(".post_json", envir = ns, inherits = FALSE)

with_stubbed_post_json <- function(stub, expr) {
    assignInNamespace(".post_json", stub, ns = "llm.api")
    tryCatch(force(expr),
             finally = assignInNamespace(".post_json", orig_post_json,
                                         ns = "llm.api"))
}

# --- Anthropic: fires for assistant + each tool_result block --------
# Two-stage stub: first call returns an assistant message with two
# tool_use blocks; second call returns text-only (end of turn).
anth_call_count <- 0L
anth_stub <- function(url, body, headers) {
    anth_call_count <<- anth_call_count + 1L
    if (anth_call_count == 1L) {
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
             content = list(list(type = "text", text = "all done")),
             usage = list(input_tokens = 12L, output_tokens = 3L)
        )
    }
}

anth_snapshots <- list()
anth_record <- function(messages) {
    anth_snapshots[[length(anth_snapshots) + 1L]] <<- list(
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

anth_result <- with_stubbed_post_json(anth_stub, llm.api::agent(
                                                                prompt = "go",
                                                                tools = list(list(name = "echo", description = "d",
                                                                                  input_schema = list(type = "object"))),
                                                                tool_handler = function(name, args) sprintf("res-%s", args$x),
                                                                model = "claude-test",
                                                                provider = "anthropic",
                                                                verbose = FALSE,
                                                                history_callback = anth_record
))

expect_equal(anth_result$content, "all done")
expect_equal(anth_call_count, 2L)

# Callback should have fired exactly four times:
#   1. After first assistant message (with 2 tool_uses)
#   2. After first tool_result block appended to a new user message
#   3. After second tool_result block extended that same user message
#   4. After the final text-only assistant message
expect_equal(length(anth_snapshots), 4L)
expect_equal(anth_snapshots[[1L]]$length, 2L)
expect_equal(anth_snapshots[[1L]]$last_role, "assistant")
expect_equal(anth_snapshots[[2L]]$length, 3L)
expect_equal(anth_snapshots[[2L]]$last_role, "user")
expect_equal(anth_snapshots[[2L]]$last_content_n, 1L)
expect_equal(anth_snapshots[[3L]]$length, 3L)
expect_equal(anth_snapshots[[3L]]$last_role, "user")
expect_equal(anth_snapshots[[3L]]$last_content_n, 2L)
expect_equal(anth_snapshots[[4L]]$length, 4L)
expect_equal(anth_snapshots[[4L]]$last_role, "assistant")

# --- OpenAI / Moonshot / Ollama: each tool_result is its own message
# Mirrors the Anthropic test but uses OpenAI's chat-completions
# response shape with a separate role="tool" message per result.
oai_call_count <- 0L
oai_stub <- function(url, body, headers) {
    oai_call_count <<- oai_call_count + 1L
    if (oai_call_count == 1L) {
        list(
             choices = list(list(
                                 message = list(
                                                role = "assistant",
                                                content = "",
                                                tool_calls = list(
                                                                  list(id = "call_1", type = "function",
                                                                       `function` = list(name = "echo",
                                                                                         arguments = "{\"x\":1}")),
                                                                  list(id = "call_2", type = "function",
                                                                       `function` = list(name = "echo",
                                                                                         arguments = "{\"x\":2}"))
                                ),
                                                finish_reason = "tool_calls"
                )
            )),
             usage = list(prompt_tokens = 10L, completion_tokens = 5L)
        )
    } else {
        list(
             choices = list(list(
                                 message = list(role = "assistant", content = "all done"),
                                 finish_reason = "stop"
            )),
             usage = list(prompt_tokens = 12L, completion_tokens = 3L)
        )
    }
}

oai_snapshots <- list()
oai_record <- function(messages) {
    last <- messages[[length(messages)]]
    oai_snapshots[[length(oai_snapshots) + 1L]] <<- list(
                                                         length = length(messages),
                                                         last_role = last$role,
                                                         last_tool_call_id = last$tool_call_id %||% NA_character_
    )
}

oai_result <- with_stubbed_post_json(oai_stub, llm.api::agent(
                                                              prompt = "go",
                                                              tools = list(list(type = "function",
                                                                                `function` = list(name = "echo", description = "d"))),
                                                              tool_handler = function(name, args) sprintf("res-%s", args$x),
                                                              model = "gpt-4o-test",
                                                              provider = "openai",
                                                              verbose = FALSE,
                                                              history_callback = oai_record
))

expect_equal(oai_result$content, "all done")
expect_equal(oai_call_count, 2L)

# Same four fires, but on OpenAI each tool result becomes its OWN
# role="tool" message rather than extending one user message.
#   1. After assistant message (with both tool_calls)
#   2. After first tool message (role="tool", tool_call_id="call_1")
#   3. After second tool message (role="tool", tool_call_id="call_2")
#   4. After final assistant text message
expect_equal(length(oai_snapshots), 4L)
expect_equal(oai_snapshots[[1L]]$length, 2L)
expect_equal(oai_snapshots[[1L]]$last_role, "assistant")
expect_equal(oai_snapshots[[2L]]$length, 3L)
expect_equal(oai_snapshots[[2L]]$last_role, "tool")
expect_equal(oai_snapshots[[2L]]$last_tool_call_id, "call_1")
expect_equal(oai_snapshots[[3L]]$length, 4L)
expect_equal(oai_snapshots[[3L]]$last_role, "tool")
expect_equal(oai_snapshots[[3L]]$last_tool_call_id, "call_2")
expect_equal(oai_snapshots[[4L]]$length, 5L)
expect_equal(oai_snapshots[[4L]]$last_role, "assistant")

# --- Callback errors don't break the turn ---------------------------
anth_call_count <- 0L
boom_result <- with_stubbed_post_json(anth_stub, llm.api::agent(
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
))

expect_equal(boom_result$content, "all done")
expect_equal(length(boom_result$history), 4L)
