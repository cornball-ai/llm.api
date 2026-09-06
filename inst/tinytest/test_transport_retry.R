# Transport resilience on the agent path.
#
# An ARC-AGI-3 game on claude-opus-5 was at 8 of 9 levels when one
# request to api.anthropic.com went silent for ten minutes. R's curl
# aborted it ("Operation too slow"), the error unwound the process and
# 55 minutes of play died with it. Two changes: the Anthropic agent
# path always streams, so a long generation keeps bytes flowing and
# the silence cutoff only trips on a genuine stall; and a request the
# transport lost before any byte arrived is retried once.

library(tinytest)
options(llm.api.transport_wait = 0)

curl_err <- function(msg = "Timeout was reached") {
    structure(class = c("curl_error_operation_timedout", "curl_error",
                        "error", "condition"),
              list(message = msg, call = NULL))
}

# --- .llm_is_transport_error --------------------------------------------
# curl_fetch_memory() signals a classed curl_error; curl_fetch_stream()
# signals a plain error carrying libcurl's text. Both are the
# transport's. An API error and an R error are not.

is_te <- llm.api:::.llm_is_transport_error
expect_true(is_te(curl_err()))
expect_true(is_te(simpleError(paste(
    "Timeout was reached [api.anthropic.com]: Operation too slow.",
    "Less than 1 bytes/sec transferred the last 600 seconds"))))
expect_true(is_te(simpleError(paste(
    "Failed to open 'http://127.0.0.1:9/': Failed to connect to",
    "127.0.0.1 port 9 after 0 ms: Couldn't connect to server"))))
expect_true(is_te(simpleError("Recv failure: Connection reset by peer")))
# the streaming path's real shape: generic error, libcurl text in a warning
expect_true(is_te(simpleError("cannot open the connection"),
                  notes = "Failed to open 'http://x': Couldn't connect to server"))
expect_false(is_te(simpleError("API error (400): messages: roles must alternate")))
expect_false(is_te(simpleError("API error (429): rate limit")))
expect_false(is_te(simpleError("object of type 'closure' is not subsettable")))

# --- .llm_transport_retry ---------------------------------------------

# a curl error with nothing received: one retry, second value returned
calls <- 0L
res <- llm.api:::.llm_transport_retry(function() {
    calls <<- calls + 1L
    if (calls == 1L) stop(curl_err())
    "ok"
})
expect_equal(res, "ok")
expect_equal(calls, 2L)

# a second curl error propagates: one retry, not a loop
calls <- 0L
expect_error(llm.api:::.llm_transport_retry(function() {
    calls <<- calls + 1L
    stop(curl_err("still down"))
}), "still down")
expect_equal(calls, 2L)

# an error that is not the transport's is not retried
calls <- 0L
expect_error(llm.api:::.llm_transport_retry(function() {
    calls <<- calls + 1L
    stop("API error (400): bad request")
}), "API error")
expect_equal(calls, 1L)

# a request that had started to answer is not retried: re-sending it
# would bill the generation twice
calls <- 0L
expect_error(llm.api:::.llm_transport_retry(function() {
    calls <<- calls + 1L
    stop(curl_err())
}, received = function() TRUE), "Timeout")
expect_equal(calls, 1L)

# --- the transports actually go through it ----------------------------
# A refused port gives a real curl error with nothing received. With
# the wait set to one second, a retry is visible as elapsed time; the
# error still propagates after it.

options(llm.api.transport_wait = 1)
t0 <- Sys.time()
expect_error(llm.api:::.post_json("http://127.0.0.1:9/v1/messages",
                                  list(messages = list()), character()),
             class = "curl_error")
expect_true(as.numeric(Sys.time() - t0, units = "secs") >= 1)

# the streaming transport raises a plain error with libcurl's text, and
# warns on each failed open (one per attempt)
t0 <- Sys.time()
expect_warning(expect_error(
    llm.api:::.anthropic_post_sse("http://127.0.0.1:9/v1/messages",
                                  list(messages = list()), character()),
    "connect"))
expect_true(as.numeric(Sys.time() - t0, units = "secs") >= 1)
options(llm.api.transport_wait = 0)

# --- the Anthropic agent path streams -----------------------------------
# No on_delta, and the request still goes to the SSE transport; the
# plain POST is stubbed to fail so a regression to it cannot pass.

ns <- asNamespace("llm.api")
orig_sse <- get(".anthropic_post_sse", envir = ns, inherits = FALSE)
orig_post <- get(".post_json", envir = ns, inherits = FALSE)

seen <- NULL
sse_stub <- function(url, body, headers, on_delta = NULL) {
    seen <<- list(url = url, body = body, on_delta = on_delta)
    list(content = list(list(type = "text", text = "streamed hello")),
         usage = list(input_tokens = 1L, output_tokens = 1L),
         stop_reason = "end_turn", role = "assistant", type = "message")
}
post_stub <- function(url, body, headers) {
    stop("plain POST used on the Anthropic agent path")
}
assignInNamespace(".anthropic_post_sse", sse_stub, ns = "llm.api")
assignInNamespace(".post_json", post_stub, ns = "llm.api")
res <- tryCatch(
    llm.api:::.agent_anthropic(
        messages = list(list(role = "user", content = "hi")),
        tools = list(), system = NULL, model = "claude-opus-5",
        config = list(api_key = "x", base_url = "https://example.invalid",
                      chat_path = "/v1/messages")),
    finally = {
        assignInNamespace(".anthropic_post_sse", orig_sse, ns = "llm.api")
        assignInNamespace(".post_json", orig_post, ns = "llm.api")
    })
expect_false(is.null(seen))
expect_null(seen$on_delta)
expect_equal(seen$url, "https://example.invalid/v1/messages")
expect_true(any(grepl("streamed hello", unlist(res), fixed = TRUE)))
