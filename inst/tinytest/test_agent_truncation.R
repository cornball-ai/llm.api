# A response cut off at the output-token budget must not present as a
# clean completion (#38): its tool calls don't execute, the partial
# assistant message is not appended to history, and the return is
# marked. Offline: stubs llm.api:::.post_json, restoring via finally.

ns <- asNamespace("llm.api")
orig_post_json <- get(".post_json", envir = ns, inherits = FALSE)
with_stubbed_post_json <- function(stub, expr) {
    assignInNamespace(".post_json", stub, ns = "llm.api")
    tryCatch(force(expr),
             finally = assignInNamespace(".post_json", orig_post_json,
                                         ns = "llm.api"))
}

echo_tools <- list(list(name = "echo", description = "d",
                        input_schema = list(type = "object")))
marker <- "[Output truncated: max_tokens]"

# --- anthropic wire: truncation mid-tool-call, partial block delivered ---
# The cap cut generation during tool input, so the block arrives with
# empty arguments and stop_reason "max_tokens". The handler must not
# run with those arguments.
handler_calls <- 0L
stub_tool <- function(url, body, headers) {
    list(content = list(list(type = "tool_use", id = "tu_1",
                             name = "echo", input = list())),
         stop_reason = "max_tokens",
         usage = list(input_tokens = 10L, output_tokens = 30L))
}
expect_warning(
    res <- with_stubbed_post_json(stub_tool, llm.api::agent(
        prompt = "go", tools = echo_tools,
        tool_handler = function(name, args) {
            handler_calls <<- handler_calls + 1L
            "should never run"
        },
        model = "claude-test", provider = "anthropic", verbose = FALSE)),
    pattern = "truncated")
expect_identical(handler_calls, 0L)
expect_true(isTRUE(res$truncated))
expect_identical(res$content, marker)
expect_identical(res$turns, 1L)
# Partial assistant message not appended: history is just the prompt.
expect_identical(length(res$history), 1L)
expect_identical(res$history[[1L]]$role, "user")
# The truncated turn's tokens still count.
expect_identical(res$usage$output_tokens, 30L)

# --- anthropic wire: truncation after some text keeps the text ---
stub_text <- function(url, body, headers) {
    list(content = list(list(type = "text", text = "partial thought")),
         stop_reason = "max_tokens",
         usage = list(input_tokens = 5L, output_tokens = 30L))
}
res2 <- suppressWarnings(with_stubbed_post_json(stub_text, llm.api::agent(
    prompt = "go", model = "claude-test", provider = "anthropic",
    verbose = FALSE)))
expect_true(isTRUE(res2$truncated))
expect_identical(res2$content, paste0("partial thought\n\n", marker))

# --- control: a clean end_turn is unmarked ---
stub_done <- function(url, body, headers) {
    list(content = list(list(type = "text", text = "done")),
         stop_reason = "end_turn",
         usage = list(input_tokens = 5L, output_tokens = 2L))
}
res3 <- with_stubbed_post_json(stub_done, llm.api::agent(
    prompt = "go", model = "claude-test", provider = "anthropic",
    verbose = FALSE))
expect_identical(res3$content, "done")
expect_null(res3$truncated)

# --- chat-completions wire (via key-free ollama): finish_reason "length" ---
# The dropped-call shape: the cap hit before the tool call was emitted,
# so the choice has no tool_calls and would otherwise read as done.
stub_cc <- function(url, body, headers) {
    list(choices = list(list(
             message = list(role = "assistant", content = NULL),
             finish_reason = "length")),
         usage = list(prompt_tokens = 10L, completion_tokens = 30L))
}
res4 <- suppressWarnings(with_stubbed_post_json(stub_cc, llm.api::agent(
    prompt = "go", tools = echo_tools,
    tool_handler = function(name, args) "should never run",
    model = "test-model", provider = "ollama", verbose = FALSE)))
expect_true(isTRUE(res4$truncated))
expect_identical(res4$content, marker)
expect_identical(length(res4$history), 1L)

# --- responses wire: status "incomplete" marks the parse ---
fake_incomplete <- list(
    status = "incomplete",
    incomplete_details = list(reason = "max_output_tokens"),
    output = list(),
    usage = list(input_tokens = 10L, output_tokens = 30L))
parsed <- llm.api:::.openai_codex_parse_response(fake_incomplete)
expect_true(isTRUE(parsed$truncated))
fake_done <- list(status = "completed",
                  output = list(list(type = "message",
                                     content = list(list(text = "hi")))),
                  usage = list(input_tokens = 1L, output_tokens = 1L))
expect_false(llm.api:::.openai_codex_parse_response(fake_done)$truncated)

# --- anthropic wire: context-window overflow is the other truncation ---
# stop_reason "model_context_window_exceeded" also leaves a partial
# tool_use; it must gate identically, with its own reason and marker
# (raising max_tokens would not help, so the advice differs too).
ctx_calls <- 0L
stub_ctx <- function(url, body, headers) {
    list(content = list(list(type = "tool_use", id = "tu_2",
                             name = "echo", input = list())),
         stop_reason = "model_context_window_exceeded",
         usage = list(input_tokens = 190000L, output_tokens = 4L))
}
expect_warning(
    res_ctx <- with_stubbed_post_json(stub_ctx, llm.api::agent(
        prompt = "go", tools = echo_tools,
        tool_handler = function(name, args) {
            ctx_calls <<- ctx_calls + 1L
            "should never run"
        },
        model = "claude-test", provider = "anthropic", verbose = FALSE)),
    pattern = "context window")
expect_identical(ctx_calls, 0L)
expect_true(isTRUE(res_ctx$truncated))
expect_identical(res_ctx$truncation_reason, "model_context_window_exceeded")
expect_identical(res_ctx$content,
                 "[Output truncated: model_context_window_exceeded]")

# --- responses wire: reason split, including content_filter ---
fake_filtered <- list(
    status = "incomplete",
    incomplete_details = list(reason = "content_filter"),
    output = list(),
    usage = list(input_tokens = 10L, output_tokens = 30L))
parsed_cf <- llm.api:::.openai_codex_parse_response(fake_filtered)
expect_true(isTRUE(parsed_cf$truncated))
expect_identical(parsed_cf$truncation_reason, "content_filter")

# chat()'s Responses paths map the split onto the documented
# finish_reason vocabulary: "stop" / "length" / literal otherwise.
expect_identical(llm.api:::.openai_responses_finish_reason(
    list(truncated = FALSE)), "stop")
expect_identical(llm.api:::.openai_responses_finish_reason(
    list(truncated = TRUE, truncation_reason = "max_output_tokens")),
    "length")
expect_identical(llm.api:::.openai_responses_finish_reason(
    list(truncated = TRUE, truncation_reason = "content_filter")),
    "content_filter")

# --- streamed: the terminal SSE events carry the cutoff end to end ---
# Each wire's *real* assembler runs over fixture events (file:// URLs
# stream through curl_fetch_stream like any other transport); only the
# URL is swapped, exactly because this regression was a wiring failure.
sse_file <- function(lines) {
    path <- tempfile(fileext = ".sse")
    writeLines(lines, path)
    paste0("file://", normalizePath(path, winslash = "/"))
}
anthropic_sse <- function(events) {
    sse_file(unlist(lapply(events, function(e) {
        ty <- sub('^.*?"type":"([^"]+)".*$', "\\1", e)
        c(paste0("event: ", ty), paste0("data: ", e), "")
    })))
}
data_sse <- function(events) {
    sse_file(c(unlist(lapply(events, function(e) {
        c(paste0("data: ", e), "")
    })), "data: [DONE]", ""))
}
with_stubbed_sse <- function(fn_name, fixture_url, expr) {
    orig <- get(fn_name, envir = ns, inherits = FALSE)
    stub <- function(url, body, headers, on_delta = NULL) {
        orig(fixture_url, body, headers, on_delta = on_delta)
    }
    assignInNamespace(fn_name, stub, ns = "llm.api")
    tryCatch(force(expr),
             finally = assignInNamespace(fn_name, orig, ns = "llm.api"))
}
swallow <- function(x) NULL

# anthropic: partial tool_use spliced from input_json_delta fragments,
# stop_reason max_tokens at message_delta
anthropic_truncated <- function(reason) anthropic_sse(c(
    '{"type":"message_start","message":{"usage":{"input_tokens":11}}}',
    paste0('{"type":"content_block_start","index":0,',
           '"content_block":{"type":"tool_use","id":"tu9",',
           '"name":"echo","input":{}}}'),
    paste0('{"type":"content_block_delta","index":0,',
           '"delta":{"type":"input_json_delta",',
           '"partial_json":"{\\"x\\": \\"lo"}}'),
    '{"type":"content_block_stop","index":0}',
    paste0('{"type":"message_delta","delta":{"stop_reason":"', reason,
           '"},"usage":{"output_tokens":30}}'),
    '{"type":"message_stop"}'))
stream_calls <- 0L
res_s1 <- suppressWarnings(with_stubbed_sse(
    ".anthropic_post_sse", anthropic_truncated("max_tokens"),
    llm.api::agent(prompt = "go", tools = echo_tools,
                   tool_handler = function(name, args) {
                       stream_calls <<- stream_calls + 1L
                       "should never run"
                   },
                   model = "claude-test", provider = "anthropic",
                   verbose = FALSE, on_delta = swallow)))
expect_identical(stream_calls, 0L)
expect_true(isTRUE(res_s1$truncated))
expect_identical(res_s1$truncation_reason, "max_tokens")
expect_identical(res_s1$content, marker)

res_s2 <- suppressWarnings(with_stubbed_sse(
    ".anthropic_post_sse",
    anthropic_truncated("model_context_window_exceeded"),
    llm.api::agent(prompt = "go", tools = echo_tools,
                   tool_handler = function(name, args) {
                       stream_calls <<- stream_calls + 1L
                       "should never run"
                   },
                   model = "claude-test", provider = "anthropic",
                   verbose = FALSE, on_delta = swallow)))
expect_identical(stream_calls, 0L)
expect_identical(res_s2$truncation_reason, "model_context_window_exceeded")

# chat-completions (key-free ollama): tool-call fragments, then
# finish_reason "length" on the terminal chunk
cc_truncated <- data_sse(c(
    paste0('{"choices":[{"index":0,"delta":{"role":"assistant"},',
           '"finish_reason":null}]}'),
    paste0('{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,',
           '"id":"c1","type":"function","function":{"name":"echo",',
           '"arguments":"{\\"x\\":"}}]},"finish_reason":null}]}'),
    paste0('{"choices":[{"index":0,"delta":{},"finish_reason":"length"}],',
           '"usage":{"prompt_tokens":9,"completion_tokens":30}}')))
res_s3 <- suppressWarnings(with_stubbed_sse(
    ".openai_cc_post_sse", cc_truncated,
    llm.api::agent(prompt = "go", tools = echo_tools,
                   tool_handler = function(name, args) {
                       stream_calls <<- stream_calls + 1L
                       "should never run"
                   },
                   model = "test-model", provider = "ollama",
                   verbose = FALSE, on_delta = swallow)))
expect_identical(stream_calls, 0L)
expect_true(isTRUE(res_s3$truncated))
expect_identical(res_s3$truncation_reason, "length")
expect_identical(res_s3$content, marker)

# responses wire (openai + web_search routes over it): a function_call
# item lands via output_item.done, then response.incomplete
responses_truncated <- function(reason) data_sse(c(
    paste0('{"type":"response.output_item.done","output_index":0,',
           '"item":{"type":"function_call","call_id":"c2",',
           '"name":"echo","arguments":"{\\"x\\":1"}}'),
    paste0('{"type":"response.incomplete","response":{"status":',
           '"incomplete","incomplete_details":{"reason":"', reason,
           '"},"output":[],"usage":{"input_tokens":8,',
           '"output_tokens":30}}}')))
res_s4 <- suppressWarnings(with_stubbed_sse(
    ".openai_codex_post_sse", responses_truncated("max_output_tokens"),
    llm.api::agent(prompt = "go", tools = echo_tools,
                   tool_handler = function(name, args) {
                       stream_calls <<- stream_calls + 1L
                       "should never run"
                   },
                   model = "gpt-test", provider = "openai",
                   web_search = TRUE, verbose = FALSE,
                   on_delta = swallow)))
expect_identical(stream_calls, 0L)
expect_true(isTRUE(res_s4$truncated))
expect_identical(res_s4$truncation_reason, "max_output_tokens")
expect_identical(res_s4$content, marker)

# content_filter through the same path: fail closed, accurately named
expect_warning(
    res_s5 <- with_stubbed_sse(
        ".openai_codex_post_sse", responses_truncated("content_filter"),
        llm.api::agent(prompt = "go", tools = echo_tools,
                       tool_handler = function(name, args) {
                           stream_calls <<- stream_calls + 1L
                           "should never run"
                       },
                       model = "gpt-test", provider = "openai",
                       web_search = TRUE, verbose = FALSE,
                       on_delta = swallow)),
    pattern = "incomplete")
expect_identical(stream_calls, 0L)
expect_identical(res_s5$truncation_reason, "content_filter")
expect_identical(res_s5$content, "[Response incomplete: content_filter]")

# --- live: a 30-token budget cannot finish emitting a tool call ---
if (at_home() && nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) {
    live_calls <- 0L
    res_live <- suppressWarnings(llm.api::agent(
        prompt = paste("Call the echo tool immediately with a long",
                       "sentence as input. Do not write any prose."),
        tools = echo_tools,
        tool_handler = function(name, args) {
            live_calls <<- live_calls + 1L
            "42"
        },
        model = "claude-haiku-4-5", provider = "anthropic",
        max_turns = 3, verbose = FALSE, max_tokens = 30))
    expect_true(isTRUE(res_live$truncated))
    expect_identical(live_calls, 0L)
    expect_true(grepl(marker, res_live$content, fixed = TRUE))
}
