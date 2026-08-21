# Streaming over the Chat Completions wire.
#
# The assertion that matters is the last one: a turn's history must come
# out identical() streamed and non-streamed. Tool-call arguments arrive
# as string fragments and get spliced back together, and a splice that
# drops or misorders a fragment produces valid JSON that calls the wrong
# tool. Field-by-field assertions are exactly how that passes.

sse_url <- function(events) {
    path <- tempfile(fileext = ".sse")
    writeLines(c(paste0("data: ", events, "\n"), "data: [DONE]\n"), path)
    paste0("file://", normalizePath(path, winslash = "/"))
}

post <- function(events, on_delta = NULL) {
    llm.api:::.openai_cc_post_sse(sse_url(events),
                                  list(model = "m", messages = list()),
                                  character(), on_delta = on_delta)
}

# --- Text ---

local({
    deltas <- character()
    resp <- post(c(
        '{"choices":[{"delta":{"role":"assistant","content":"Hel"}}]}',
        '{"choices":[{"delta":{"content":"lo"}}]}',
        '{"choices":[{"delta":{},"finish_reason":"stop"}]}',
        '{"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":2}}'),
        on_delta = function(x) deltas <<- c(deltas, x))
    expect_identical(deltas, c("Hel", "lo"))
    expect_identical(resp$choices[[1L]]$message$content, "Hello")
    expect_identical(resp$choices[[1L]]$message$role, "assistant")
    expect_identical(resp$choices[[1L]]$finish_reason, "stop")
    # Usage rides the final choices-less chunk. Without stream_options
    # it never arrives and every cost downstream silently becomes zero,
    # which reads as a free model rather than a missing field.
    expect_identical(resp$usage$prompt_tokens, 5L)
    expect_identical(resp$usage$completion_tokens, 2L)
})

# stream_options is asked for, and a caller's own choice is not
# overwritten.
local({
    body <- list(model = "m", messages = list())
    expect_identical(
        llm.api:::.openai_cc_post_sse(sse_url('{"choices":[]}'), body,
                                      character())$usage, NULL)
})

# --- Tool-call fragment reassembly ---

# Arguments split across chunks are spliced back in order.
local({
    resp <- post(c(
        paste0('{"choices":[{"delta":{"tool_calls":[{"index":0,',
               '"id":"call_1","type":"function",',
               '"function":{"name":"get_weather","arguments":""}}]}}]}'),
        paste0('{"choices":[{"delta":{"tool_calls":[{"index":0,',
               '"function":{"arguments":"{\\"city\\":"}}]}}]}'),
        paste0('{"choices":[{"delta":{"tool_calls":[{"index":0,',
               '"function":{"arguments":"\\"Chicago\\"}"}}]}}]}'),
        '{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}'))
    tcs <- resp$choices[[1L]]$message$tool_calls
    expect_identical(length(tcs), 1L)
    expect_identical(tcs[[1L]]$id, "call_1")
    expect_identical(tcs[[1L]][["function"]]$name, "get_weather")
    # By value. A splice that dropped a fragment still parses as JSON.
    expect_identical(tcs[[1L]][["function"]]$arguments,
                     '{"city":"Chicago"}')
    # Content is NULL, not "", alongside a tool call -- which is what
    # the non-streamed wire sends.
    expect_null(resp$choices[[1L]]$message$content)
})

# Two calls whose fragments interleave. Keyed on the wire's `index`,
# not arrival order: appending in arrival order braids them into each
# other and produces two valid, wrong argument strings.
local({
    resp <- post(c(
        paste0('{"choices":[{"delta":{"tool_calls":[',
               '{"index":0,"id":"a","function":{"name":"one","arguments":"{\\"x\\":"}},',
               '{"index":1,"id":"b","function":{"name":"two","arguments":"{\\"y\\":"}}',
               ']}}]}'),
        paste0('{"choices":[{"delta":{"tool_calls":[',
               '{"index":1,"function":{"arguments":"2}"}},',
               '{"index":0,"function":{"arguments":"1}"}}',
               ']}}]}'),
        '{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}'))
    tcs <- resp$choices[[1L]]$message$tool_calls
    expect_identical(length(tcs), 2L)
    # Index order, not arrival order.
    expect_identical(tcs[[1L]]$id, "a")
    expect_identical(tcs[[2L]]$id, "b")
    expect_identical(tcs[[1L]][["function"]]$arguments, '{"x":1}')
    expect_identical(tcs[[2L]][["function"]]$arguments, '{"y":2}')
})

# A call whose index arrives out of order still lands in index order.
local({
    resp <- post(c(
        paste0('{"choices":[{"delta":{"tool_calls":[{"index":1,"id":"b",',
               '"function":{"name":"two","arguments":"{}"}}]}}]}'),
        paste0('{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a",',
               '"function":{"name":"one","arguments":"{}"}}]}}]}')))
    tcs <- resp$choices[[1L]]$message$tool_calls
    expect_identical(vapply(tcs, function(t) t$id, character(1)),
                     c("a", "b"))
})

# --- Cancellation ---

local({
    deltas <- character()
    resp <- post(c(
        '{"choices":[{"delta":{"content":"one "}}]}',
        '{"choices":[{"delta":{"content":"two "}}]}',
        '{"choices":[{"delta":{"content":"three"}}]}'),
        on_delta = function(x) {
            deltas <<- c(deltas, x)
            if (length(deltas) >= 2L) {
                llm.api::llm_cancel()
            }
        })
    expect_identical(deltas, c("one ", "two "))
    expect_true(isTRUE(attr(resp, "llm_cancelled")))
    # What it managed to say, by value.
    expect_identical(resp$choices[[1L]]$message$content, "one two ")
})

# --- Streamed and non-streamed agree ---
# The one that would catch a reassembly bug. Both paths are driven
# through .agent_openai with the transport stubbed, and the whole
# returned record is compared -- not a field at a time.

ns <- asNamespace("llm.api")
with_stub <- function(name, stub, expr) {
    orig <- get(name, envir = ns, inherits = FALSE)
    assignInNamespace(name, stub, ns = "llm.api")
    on.exit(assignInNamespace(name, orig, ns = "llm.api"), add = TRUE)
    force(expr)
}

local({
    # The same turn, in the two shapes the wire actually sends it: one
    # whole message, and the fragments it would have been split into.
    whole <- list(choices = list(list(
        message = list(role = "assistant", content = NULL,
                       tool_calls = list(
                           list(id = "call_1", type = "function",
                                `function` = list(name = "get_weather",
                                    arguments = '{"city":"Chicago"}')),
                           list(id = "call_2", type = "function",
                                `function` = list(name = "get_time",
                                    arguments = '{"tz":"CST"}')))),
        finish_reason = "tool_calls")),
        usage = list(prompt_tokens = 9L, completion_tokens = 4L))

    fragments <- c(
        paste0('{"choices":[{"delta":{"role":"assistant","tool_calls":[',
               '{"index":0,"id":"call_1","type":"function",',
               '"function":{"name":"get_weather","arguments":"{\\"ci"}}]}}]}'),
        paste0('{"choices":[{"delta":{"tool_calls":[{"index":0,',
               '"function":{"arguments":"ty\\":\\"Chicago\\"}"}}]}}]}'),
        paste0('{"choices":[{"delta":{"tool_calls":[',
               '{"index":1,"id":"call_2","type":"function",',
               '"function":{"name":"get_time","arguments":"{\\"tz\\""}}]}}]}'),
        paste0('{"choices":[{"delta":{"tool_calls":[{"index":1,',
               '"function":{"arguments":":\\"CST\\"}"}}]}}]}'),
        '{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
        '{"choices":[],"usage":{"prompt_tokens":9,"completion_tokens":4}}')

    plain <- with_stub(".post_json", function(url, body, headers) whole,
        llm.api:::.agent_openai(list(), list(), NULL, "m",
            list(provider = "openai", base_url = "http://127.0.0.1:1",
                 chat_path = "/v1/chat/completions", api_key = "k")))

    # The streaming side is driven through the real .openai_cc_post_sse
    # by pointing the config's URL at the fixture, rather than stubbing
    # the function under test. A stub that called the original would be
    # calling itself -- which is what the first version of this did, and
    # R answered "evaluation nested too deeply" rather than anything
    # about streaming.
    streamed <- llm.api:::.agent_openai(list(), list(), NULL, "m",
        list(provider = "openai", base_url = sse_url(fragments),
             chat_path = "", api_key = "k"),
        on_delta = function(x) NULL)

    # The whole record, not a field at a time. A codec that drops one
    # field is exactly what a field-by-field comparison waves through.
    expect_identical(streamed, plain)
})
