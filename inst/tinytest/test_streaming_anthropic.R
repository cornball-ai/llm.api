# Streaming over the Anthropic Messages wire.
#
# A third event vocabulary: content arrives as indexed blocks that open,
# take deltas, and close, and a tool call's arguments stream as
# `partial_json` fragments that are spliced and only then parsed. A
# dropped fragment gives a parse failure or -- worse -- a shorter object
# that still parses into valid-looking arguments.

sse_url <- function(events) {
    path <- tempfile(fileext = ".sse")
    # The `event:` lines are here because Anthropic sends them. The data
    # payload carries its own `type`, so they should be skipped rather
    # than parsed; a fixture without them cannot catch a reader that
    # chokes on one.
    lines <- unlist(lapply(events, function(e) {
        ty <- sub('^.*"type":"([^"]+)".*$', "\\1", e)
        c(paste0("event: ", ty), paste0("data: ", e), "")
    }))
    writeLines(lines, path)
    paste0("file://", normalizePath(path, winslash = "/"))
}

post <- function(events, on_delta = NULL) {
    llm.api:::.anthropic_post_sse(sse_url(events),
                                  list(model = "m", messages = list()),
                                  character(), on_delta = on_delta)
}

# --- Text ---

local({
    deltas <- character()
    resp <- post(c(
        '{"type":"message_start","message":{"usage":{"input_tokens":11}}}',
        paste0('{"type":"content_block_start","index":0,',
               '"content_block":{"type":"text","text":""}}'),
        paste0('{"type":"content_block_delta","index":0,',
               '"delta":{"type":"text_delta","text":"Hel"}}'),
        paste0('{"type":"content_block_delta","index":0,',
               '"delta":{"type":"text_delta","text":"lo"}}'),
        '{"type":"content_block_stop","index":0}',
        paste0('{"type":"message_delta","delta":{"stop_reason":"end_turn"},',
               '"usage":{"output_tokens":4}}'),
        '{"type":"message_stop"}'), on_delta = function(x) deltas <<- c(deltas, x))
    expect_identical(deltas, c("Hel", "lo"))
    expect_identical(length(resp$content), 1L)
    expect_identical(resp$content[[1L]]$type, "text")
    expect_identical(resp$content[[1L]]$text, "Hello")
    expect_identical(resp$stop_reason, "end_turn")
    # Input tokens arrive at message_start and output tokens at
    # message_delta. Merged, not replaced: replacing loses the input
    # count and the request reads as costing nothing to send.
    expect_identical(resp$usage$input_tokens, 11L)
    expect_identical(resp$usage$output_tokens, 4L)
})

# --- Tool-call argument fragments ---

local({
    resp <- post(c(
        '{"type":"message_start","message":{"usage":{"input_tokens":9}}}',
        paste0('{"type":"content_block_start","index":0,"content_block":',
               '{"type":"tool_use","id":"toolu_1","name":"get_weather",',
               '"input":{}}}'),
        paste0('{"type":"content_block_delta","index":0,"delta":',
               '{"type":"input_json_delta","partial_json":"{\\"city\\":"}}'),
        paste0('{"type":"content_block_delta","index":0,"delta":',
               '{"type":"input_json_delta","partial_json":"\\"Chicago\\"}"}}'),
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_stop"}'))
    blk <- resp$content[[1L]]
    expect_identical(blk$type, "tool_use")
    expect_identical(blk$id, "toolu_1")
    expect_identical(blk$name, "get_weather")
    # Parsed into the object the non-streamed wire delivers, not left
    # as the JSON text it streamed as.
    expect_identical(blk$input, list(city = "Chicago"))
    # And the scaffolding field does not survive into the result.
    expect_null(blk$partial_json)
})

# A tool call with no arguments streams either "{}" or nothing at all,
# and both have to become the empty object the non-streamed wire sends.
local({
    for (frag in list(
        '{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{}"}}',
        NULL)) {
        events <- c(
            paste0('{"type":"content_block_start","index":0,"content_block":',
                   '{"type":"tool_use","id":"t","name":"now","input":{}}}'),
            frag,
            '{"type":"content_block_stop","index":0}')
        resp <- post(events)
        expect_identical(resp$content[[1L]]$input, structure(list(),
                                                             names = character()))
    }
})

# Interleaved blocks: text and a tool call open together and their
# deltas alternate. Keyed on index, so neither ends up inside the other.
local({
    resp <- post(c(
        paste0('{"type":"content_block_start","index":0,',
               '"content_block":{"type":"text","text":""}}'),
        paste0('{"type":"content_block_start","index":1,"content_block":',
               '{"type":"tool_use","id":"t2","name":"f","input":{}}}'),
        paste0('{"type":"content_block_delta","index":1,"delta":',
               '{"type":"input_json_delta","partial_json":"{\\"a\\":"}}'),
        paste0('{"type":"content_block_delta","index":0,',
               '"delta":{"type":"text_delta","text":"thinking..."}}'),
        paste0('{"type":"content_block_delta","index":1,"delta":',
               '{"type":"input_json_delta","partial_json":"1}"}}'),
        '{"type":"content_block_stop","index":1}',
        '{"type":"content_block_stop","index":0}'))
    expect_identical(length(resp$content), 2L)
    expect_identical(resp$content[[1L]]$text, "thinking...")
    expect_identical(resp$content[[2L]]$input, list(a = 1L))
})

# --- Cancellation ---

local({
    deltas <- character()
    resp <- post(c(
        paste0('{"type":"content_block_start","index":0,',
               '"content_block":{"type":"text","text":""}}'),
        paste0('{"type":"content_block_delta","index":0,',
               '"delta":{"type":"text_delta","text":"one "}}'),
        paste0('{"type":"content_block_delta","index":0,',
               '"delta":{"type":"text_delta","text":"two "}}'),
        paste0('{"type":"content_block_delta","index":0,',
               '"delta":{"type":"text_delta","text":"three"}}')),
        on_delta = function(x) {
            deltas <<- c(deltas, x)
            if (length(deltas) >= 2L) {
                llm.api::llm_cancel()
            }
        })
    expect_identical(deltas, c("one ", "two "))
    expect_true(isTRUE(attr(resp, "llm_cancelled")))
    expect_identical(resp$content[[1L]]$text, "one two ")
})

# An error event is an error, not an empty response.
expect_error(
    post('{"type":"error","error":{"type":"overloaded_error","message":"slow down"}}'),
    "slow down")

# --- Streamed and non-streamed agree ---

ns <- asNamespace("llm.api")
with_stub <- function(name, stub, expr) {
    orig <- get(name, envir = ns, inherits = FALSE)
    assignInNamespace(name, stub, ns = "llm.api")
    on.exit(assignInNamespace(name, orig, ns = "llm.api"), add = TRUE)
    force(expr)
}

local({
    whole <- list(
        content = list(
            list(type = "text", text = "Looking that up."),
            list(type = "tool_use", id = "toolu_1", name = "get_weather",
                 input = list(city = "Chicago"))),
        usage = list(input_tokens = 9L, output_tokens = 5L),
        stop_reason = "tool_use", role = "assistant", type = "message")

    fragments <- c(
        '{"type":"message_start","message":{"usage":{"input_tokens":9}}}',
        paste0('{"type":"content_block_start","index":0,',
               '"content_block":{"type":"text","text":""}}'),
        paste0('{"type":"content_block_delta","index":0,',
               '"delta":{"type":"text_delta","text":"Looking "}}'),
        paste0('{"type":"content_block_delta","index":0,',
               '"delta":{"type":"text_delta","text":"that up."}}'),
        '{"type":"content_block_stop","index":0}',
        paste0('{"type":"content_block_start","index":1,"content_block":',
               '{"type":"tool_use","id":"toolu_1","name":"get_weather",',
               '"input":{}}}'),
        paste0('{"type":"content_block_delta","index":1,"delta":',
               '{"type":"input_json_delta","partial_json":"{\\"ci"}}'),
        paste0('{"type":"content_block_delta","index":1,"delta":',
               '{"type":"input_json_delta","partial_json":"ty\\":\\"Chicago\\"}"}}'),
        '{"type":"content_block_stop","index":1}',
        paste0('{"type":"message_delta","delta":{"stop_reason":"tool_use"},',
               '"usage":{"output_tokens":5}}'),
        '{"type":"message_stop"}')

    cfg <- list(provider = "anthropic", base_url = "http://127.0.0.1:1",
                chat_path = "/v1/messages", api_key = "k")

    # `plain`: what the agent path makes of the wire's whole record,
    # handed back by a stubbed transport (the agent path always streams
    # since 0.1.9.8, so the stub sits on the SSE transport).
    plain <- with_stub(".anthropic_post_sse",
        function(url, body, headers, on_delta = NULL) whole,
        llm.api:::.agent_anthropic(list(), list(), NULL, "m", cfg))

    sse_cfg <- list(provider = "anthropic", base_url = sse_url(fragments),
                    chat_path = "", api_key = "k")
    streamed <- llm.api:::.agent_anthropic(list(), list(), NULL, "m", sse_cfg,
        on_delta = function(x) NULL)
    # No callback is the agent's default now; it must assemble the same
    # record from the same fragments.
    quiet <- llm.api:::.agent_anthropic(list(), list(), NULL, "m", sse_cfg)

    # The whole record. A field-by-field comparison is how a codec that
    # drops one field passes.
    expect_identical(streamed, plain)
    expect_identical(quiet, plain)
})
