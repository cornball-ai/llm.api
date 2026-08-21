# Text as it is written, and stopping it early.
#
# The SSE transport is driven for real here rather than stubbed at the
# provider boundary: the thing under test is that a delta event reaches
# a callback and that a cancel unwinds out of curl, and neither of those
# is observable from above .openai_codex_post_sse().

# --- llm_cancel ---

# Cancelling outside a stream is an ordinary error. There is nothing to
# cancel, and a silent unwind to nowhere would be worse.
expect_error(llm.api::llm_cancel(), "cancelled by on_delta")
expect_error(llm.api::llm_cancel("barge-in"), "barge-in")

local({
    cond <- tryCatch(llm.api::llm_cancel(), condition = function(c) c)
    expect_inherits(cond, "llm_cancelled")
    # Also an error, so an uncaught one behaves like any other failure
    # instead of vanishing.
    expect_inherits(cond, "error")
})

# --- .llm_emit_delta guards ---
# A callback counting characters to decide when to start speaking must
# not be handed something that is not text.
local({
    seen <- list()
    cb <- function(x) seen[[length(seen) + 1L]] <<- x
    for (bad in list(NULL, NA_character_, "", character(0),
                     c("a", "b"), 42L, list("a"))) {
        llm.api:::.llm_emit_delta(cb, bad)
    }
    expect_identical(length(seen), 0L)
    llm.api:::.llm_emit_delta(cb, "real")
    expect_identical(seen, list("real"))
    # A NULL callback is the no-streaming case and must not error.
    expect_null(llm.api:::.llm_emit_delta(NULL, "text"))
})

# --- .llm_with_cancel ---
local({
    ok <- llm.api:::.llm_with_cancel("finished")
    expect_false(ok$cancelled)
    expect_identical(ok$value, "finished")

    cut <- llm.api:::.llm_with_cancel(llm.api::llm_cancel())
    expect_true(cut$cancelled)
    expect_null(cut$value)

    # An ordinary error is not a cancellation and must still propagate:
    # a request that failed did not succeed at stopping early.
    expect_error(llm.api:::.llm_with_cancel(stop("network is down")),
                 "network is down")
})

# --- Deltas out of a real SSE stream ---
# A local server is more work than a stub and worth it: the delta has
# to survive rawToChar, the line buffering, the JSON parse and the
# merger before it reaches the callback, and a stub skips all of that.

# Served from a file rather than a socket. curl streams file:// through
# the same write path as https, calling the callback per chunk, so the
# parsing and the cancel unwind are exercised exactly as they are in
# production -- and there is no port to collide with something already
# listening, no subprocess whose environment has to carry a helper, and
# no sleep racing a server that may not be up yet. All three of those
# went wrong before this became a file.
sse_url <- function(events) {
    path <- tempfile(fileext = ".sse")
    writeLines(paste0("data: ", events, "\n"), path)
    paste0("file://", normalizePath(path, winslash = "/"))
}

# One text delta per event, plus the completion the merger needs to
# assemble a response from.
#
# output_item.added is here because the real API sends it, and it is the
# event that made the first version of the cancel path wrong: it creates
# the message item *empty*, so a "does a message already exist" check
# finds one, skips filling in the streamed text, and returns "". Without
# this line the fixture passes either way.
delta_events <- c(
    '{"type":"response.created","response":{"output":[]}}',
    paste0('{"type":"response.output_item.added","output_index":0,',
           '"item":{"type":"message","content":[]}}'),
    '{"type":"response.output_text.delta","delta":"Hello"}',
    '{"type":"response.output_text.delta","delta":", "}',
    '{"type":"response.output_text.delta","delta":"world"}',
    paste0('{"type":"response.completed","response":{"output":[',
           '{"type":"message","content":[{"text":"Hello, world"}]}],',
           '"usage":{"input_tokens":3,"output_tokens":4}}}'))

if (!requireNamespace("curl", quietly = TRUE)) {
    exit_file("curl not installed")
}

# Every delta, in order, unsplit and unmerged -- and the assembled
# response unchanged by having been watched.
local({
    deltas <- character()
    resp <- llm.api:::.openai_codex_post_sse(
        sse_url(delta_events), list(input = list()), character(),
        on_delta = function(x) deltas <<- c(deltas, x))
    expect_identical(deltas, c("Hello", ", ", "world"))
    parsed <- llm.api:::.openai_codex_parse_response(resp)
    expect_identical(parsed$text, "Hello, world")
    expect_false(parsed$cancelled)
})

# Cancelling from the callback stops the stream. The deltas after the
# cancel never arrive, which is the whole point: the provider stops
# generating and stops charging.
local({
    deltas <- character()
    resp <- llm.api:::.openai_codex_post_sse(
        sse_url(delta_events), list(input = list()), character(),
        on_delta = function(x) {
            deltas <<- c(deltas, x)
            if (length(deltas) >= 2L) {
                llm.api::llm_cancel()
            }
        })
    expect_identical(deltas, c("Hello", ", "))
    parsed <- llm.api:::.openai_codex_parse_response(resp)
    expect_true(parsed$cancelled)
    # A cancelled response reports what it managed to say, by value.
    # The merger reconstructs a message from output_item.done and
    # ignores text deltas, so a cancelled stream -- which never reaches
    # done -- returned an empty response until the deltas were
    # accumulated separately. `expect_false(is.null(text))` passed the
    # whole time it was "": the assertion has to be the text.
    expect_identical(parsed$text, "Hello, ")
})

# No callback is the path every existing caller takes, and it must be
# untouched: same response, no error, nothing observing it.
local({
    resp <- llm.api:::.openai_codex_post_sse(
        sse_url(delta_events), list(input = list()), character())
    parsed <- llm.api:::.openai_codex_parse_response(resp)
    expect_identical(parsed$text, "Hello, world")
    expect_false(parsed$cancelled)
})

# --- agent() gating ---
# on_delta on a provider that does not stream warns rather than being
# ignored: a caller that passed a callback is building on it, and
# silence would have it believe the model simply said nothing until the
# end.
expect_warning(
    tryCatch(llm.api::agent("hi", provider = "anthropic", model = "m",
                            on_delta = function(x) x, verbose = FALSE,
                            max_turns = 1L),
             error = function(e) NULL),
    "not wired for provider")

# ... and the chat-completions providers no longer warn, because they
# stream now. This half is the one that would go quietly stale: a
# warning that stops being emitted is invisible unless something
# asserts its absence.
for (p in c("ollama", "openai", "moonshot")) {
    expect_silent(
        tryCatch(llm.api::agent("hi", provider = p, model = "m",
                                on_delta = function(x) x, verbose = FALSE,
                                max_turns = 1L),
                 error = function(e) NULL, warning = function(w) w))
}

expect_error(llm.api::agent("hi", provider = "openai_codex",
                            on_delta = "not a function", verbose = FALSE),
             "must be a function")
