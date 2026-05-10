# Tests for history_tool_calls + history_count_tool_calls.
# Pure-function, offline. Exercises both Anthropic and OpenAI shapes
# plus the unfinished-call edge case.

# ---- Empty / malformed inputs ----

expect_equal(llm.api::history_tool_calls(list()), list())
expect_equal(llm.api::history_tool_calls(NULL), list())
expect_equal(llm.api::history_count_tool_calls(list()), 0L)

# ---- Anthropic shape ----

anthropic_history <- list(
    list(role = "user", content = "find auth"),
    list(role = "assistant", content = list(
        list(type = "text", text = "Searching."),
        list(type = "tool_use", id = "tu1", name = "grep_files",
             input = list(pattern = "auth"))
    )),
    list(role = "user", content = list(
        list(type = "tool_result", tool_use_id = "tu1",
             content = list(list(type = "text", text = "src/auth.R")))
    )),
    list(role = "assistant", content = list(
        list(type = "tool_use", id = "tu2", name = "read_file",
             input = list(path = "src/auth.R"))
    )),
    list(role = "user", content = list(
        list(type = "tool_result", tool_use_id = "tu2",
             content = "auth_handler <- function() {}")
    ))
)

calls <- llm.api::history_tool_calls(anthropic_history)
expect_equal(length(calls), 2L)

expect_equal(calls[[1]]$id, "tu1")
expect_equal(calls[[1]]$name, "grep_files")
expect_equal(calls[[1]]$arguments$pattern, "auth")
expect_equal(calls[[1]]$result, "src/auth.R")
expect_true(calls[[1]]$completed)
expect_equal(calls[[1]]$call_message_index, 2L)
expect_equal(calls[[1]]$result_message_index, 3L)
expect_equal(calls[[1]]$provider_shape, "anthropic")

expect_equal(calls[[2]]$id, "tu2")
expect_equal(calls[[2]]$result, "auth_handler <- function() {}")

expect_equal(llm.api::history_count_tool_calls(anthropic_history), 2L)

# ---- OpenAI shape (covers moonshot / kimi / ollama) ----

openai_history <- list(
    list(role = "user", content = "find auth"),
    list(role = "assistant", content = "",
         tool_calls = list(
             list(id = "c1", type = "function",
                  `function` = list(name = "grep_files",
                                    arguments = "{\"pattern\":\"auth\"}")),
             list(id = "c2", type = "function",
                  `function` = list(name = "read_file",
                                    arguments = "{\"path\":\"src/auth.R\"}"))
         )),
    list(role = "tool", tool_call_id = "c1",
         name = "grep_files", content = "src/auth.R"),
    list(role = "tool", tool_call_id = "c2",
         name = "read_file", content = "auth_handler <- function() {}")
)

calls <- llm.api::history_tool_calls(openai_history)
expect_equal(length(calls), 2L)

expect_equal(calls[[1]]$id, "c1")
expect_equal(calls[[1]]$name, "grep_files")
# arguments parsed from JSON
expect_equal(calls[[1]]$arguments$pattern, "auth")
expect_equal(calls[[1]]$result, "src/auth.R")
expect_true(calls[[1]]$completed)
expect_equal(calls[[1]]$provider_shape, "openai")

expect_equal(calls[[2]]$arguments$path, "src/auth.R")
expect_equal(calls[[2]]$result, "auth_handler <- function() {}")

expect_equal(llm.api::history_count_tool_calls(openai_history), 2L)

# ---- Unfinished call (assistant emitted tool_use, no matching result) ----

unfinished_anthropic <- list(
    list(role = "user", content = "do thing"),
    list(role = "assistant", content = list(
        list(type = "tool_use", id = "tu_x", name = "bash",
             input = list(command = "ls"))
    ))
)
calls <- llm.api::history_tool_calls(unfinished_anthropic)
expect_equal(length(calls), 1L)
expect_false(calls[[1]]$completed)
expect_null(calls[[1]]$result)
expect_true(is.na(calls[[1]]$result_message_index))

# completed_only filters out the unfinished one
expect_equal(llm.api::history_count_tool_calls(unfinished_anthropic), 1L)
expect_equal(
    llm.api::history_count_tool_calls(unfinished_anthropic,
                                       completed_only = TRUE),
    0L
)

unfinished_openai <- list(
    list(role = "user", content = "do thing"),
    list(role = "assistant", content = "",
         tool_calls = list(
             list(id = "c_x", type = "function",
                  `function` = list(name = "bash",
                                    arguments = "{\"command\":\"ls\"}"))
         ))
)
calls <- llm.api::history_tool_calls(unfinished_openai)
expect_equal(length(calls), 1L)
expect_false(calls[[1]]$completed)

# ---- Mixed shapes in a single history would never happen in practice
# (a single agent call sticks to one provider), but the helper should
# at least not crash on them.

mixed <- c(anthropic_history, openai_history)
calls <- llm.api::history_tool_calls(mixed)
expect_equal(length(calls), 4L)

# ---- A user message that's a plain string contributes nothing ----

trivial <- list(
    list(role = "user", content = "hello"),
    list(role = "assistant", content = "hi back")
)
expect_equal(length(llm.api::history_tool_calls(trivial)), 0L)
expect_equal(llm.api::history_count_tool_calls(trivial), 0L)
