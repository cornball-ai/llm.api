# Verifies that .agent_ollama() writes a synthesized tool-call id back
# into the assistant_message stored in history, not just into the
# canonical $tool_calls return field. Without the writeback the history
# walk pairs assistant.tool_calls[i].id with role="tool".tool_call_id
# and they disagree, breaking history_tool_calls().
#
# Stubs llm.api:::.post_json so the test is offline.

ns <- asNamespace("llm.api")

# Snapshot original .post_json so we can restore it at the end.
orig <- get(".post_json", envir = ns, inherits = FALSE)
on_exit_called <- FALSE

# Stub: return an Ollama-shaped chat response with a tool call that
# OMITS the id field. Some Ollama models don't return an id; the bug
# we're guarding against was that the synthesized id leaked only into
# the canonical tool_calls list.
stub <- function(url, body, headers) {
    list(
        choices = list(
            list(
                message = list(
                    role = "assistant",
                    content = "",
                    tool_calls = list(
                        list(
                            type = "function",
                            # NO id field — that's the case being tested.
                            `function` = list(
                                name = "echo",
                                arguments = "{\"x\":1}"
                            )
                        )
                    )
                ),
                finish_reason = "tool_calls"
            )
        ),
        usage = list(prompt_tokens = 1, completion_tokens = 1)
    )
}

assignInNamespace(".post_json", stub, ns = "llm.api")

result <- llm.api:::.agent_ollama(
    messages = list(list(role = "user", content = "go")),
    tools = list(),
    system = NULL,
    model = "test-model",
    config = list(api_key = "x",
                  base_url = "http://stub",
                  chat_path = "/api/chat")
)

# Restore the real .post_json so other tests don't see the stub.
assignInNamespace(".post_json", orig, ns = "llm.api")

# Canonical tool_calls list got a synthesized id.
expect_equal(length(result$tool_calls), 1L)
synthesized_id <- result$tool_calls[[1]]$id
expect_true(is.character(synthesized_id) && length(synthesized_id) == 1L)
expect_true(nzchar(synthesized_id))

# The fix: the same id is now also on the assistant_message that's
# about to be appended to history. Before this fix, the id field on
# the assistant_message's tool_calls was NULL.
am_calls <- result$assistant_message$tool_calls
expect_equal(length(am_calls), 1L)
expect_equal(am_calls[[1]]$id, synthesized_id)

# Cross-check: history_tool_calls() can pair this call with a result
# message that uses the same id (the agent loop builds these via
# .add_tool_results, so we simulate the result message here).
fake_history <- list(
    list(role = "user", content = "go"),
    result$assistant_message,
    list(role = "tool",
         tool_call_id = synthesized_id,
         name = "echo",
         content = "ok")
)
calls <- llm.api::history_tool_calls(fake_history)
expect_equal(length(calls), 1L)
expect_true(calls[[1]]$completed)
expect_equal(calls[[1]]$result, "ok")
