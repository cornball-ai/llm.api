# Anthropic prompt caching on the message history, not just the system
# prompt. The marker has to (a) sit on the final cacheable block of the
# final message, (b) be the only one in the history however many
# requests preceded it, and (c) leave cache = "none" byte-identical.
# The last is checked on serialized JSON, not field by field: a
# field-by-field check is exactly how a builder that adds one field
# passes.

ns <- asNamespace("llm.api")
orig_post_json <- get(".post_json", envir = ns, inherits = FALSE)

with_stubbed_post_json <- function(stub, expr) {
    assignInNamespace(".post_json", stub, ns = "llm.api")
    tryCatch(force(expr),
             finally = assignInNamespace(".post_json", orig_post_json,
                                         ns = "llm.api"))
}

# Where the markers are: (message index, block index) pairs.
markers <- function(msgs) {
    out <- list()
    for (i in seq_along(msgs)) {
        content <- msgs[[i]]$content
        if (!is.list(content)) next
        for (j in seq_along(content)) {
            if (!is.null(content[[j]]$cache_control)) {
                out[[length(out) + 1L]] <- c(i, j)
            }
        }
    }
    out
}
json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))

mark <- llm.api:::.anthropic_mark_history

# --- the helper ------------------------------------------------------

# "none" and an empty history come back as the same object.
plain <- list(list(role = "user", content = "hi"))
expect_identical(mark(plain, "none"), plain)
expect_identical(mark(list(), "5m"), list())

# A plain-string user turn is wrapped into one marked text block.
m1 <- mark(plain, "5m")
expect_equal(length(m1[[1]]$content), 1L)
expect_equal(m1[[1]]$content[[1]]$type, "text")
expect_equal(m1[[1]]$content[[1]]$text, "hi")
expect_equal(m1[[1]]$content[[1]]$cache_control, list(type = "ephemeral"))

# A block-list turn gets the marker on its last block only.
blocks <- list(
    list(role = "user", content = "q"),
    list(role = "assistant", content = list(
        list(type = "tool_use", id = "t1", name = "f", input = list()))),
    list(role = "user", content = list(
        list(type = "tool_result", tool_use_id = "t1", content = "r1"),
        list(type = "tool_result", tool_use_id = "t2", content = "r2"))))
m2 <- mark(blocks, "5m")
expect_equal(markers(m2), list(c(3, 2)))
expect_identical(m2[[3]]$content[[1]],
                 list(type = "tool_result", tool_use_id = "t1", content = "r1"))
expect_identical(m2[[1]], blocks[[1]])         # earlier turns untouched
expect_identical(m2[[2]], blocks[[2]])

# 1h carries the TTL.
expect_equal(mark(blocks, "1h")[[3]]$content[[2]]$cache_control,
             list(type = "ephemeral", ttl = "1h"))

# Stale markers from an earlier request are stripped, so re-marking an
# already-marked history yields exactly one marker, on the new tail.
stale <- m2
stale[[4]] <- list(role = "assistant", content = list(
    list(type = "text", text = "ok")))
stale[[5]] <- list(role = "user", content = list(
    list(type = "text", text = "more")))
m3 <- mark(stale, "5m")
expect_equal(markers(m3), list(c(5, 1)))

# A trailing thinking block cannot carry a marker; it lands on the
# nearest earlier block that can.
think_tail <- list(list(role = "assistant", content = list(
    list(type = "text", text = "t"),
    list(type = "thinking", thinking = "", signature = "s"))))
expect_equal(markers(mark(think_tail, "5m")), list(c(1, 1)))
only_think <- list(list(role = "assistant", content = list(
    list(type = "redacted_thinking", data = "x"))))
expect_equal(markers(mark(only_think, "5m")), list())

# --- the chat() body builder -----------------------------------------

chat_body <- list(model = "claude-test", messages = list(
    list(role = "system", content = "sys"),
    list(role = "user", content = "hello")))

b5 <- llm.api:::.anthropic_chat_body(chat_body, cache = "5m")
expect_equal(b5$system[[1]]$cache_control$type, "ephemeral")
expect_equal(markers(b5$messages), list(c(1, 1)))
expect_equal(b5$messages[[1]]$content[[1]]$text, "hello")

# cache = "none": the messages serialize byte-for-byte as the untouched
# translation would, and system stays a bare string.
b0 <- llm.api:::.anthropic_chat_body(chat_body, cache = "none")
expect_identical(json(b0$messages),
                 json(list(list(role = "user", content = "hello"))))
expect_identical(b0$system, "sys")

# --- the agent() path, across a real loop ----------------------------
# Three requests: two tool_use rounds, then a text answer. Each request
# the loop builds must carry exactly one history marker, on the last
# block of the last message, plus the system marker -- and never one
# per prior iteration, which is what would trip the four-breakpoint
# limit on request five.
captured <- list()
n_calls <- 0L
loop_stub <- function(url, body, headers) {
    n_calls <<- n_calls + 1L
    captured[[n_calls]] <<- body
    if (n_calls <= 2L) {
        list(content = list(list(type = "tool_use", id = paste0("t", n_calls),
                                 name = "f", input = list())),
             stop_reason = "tool_use",
             usage = list(input_tokens = 1L, output_tokens = 1L))
    } else {
        list(content = list(list(type = "text", text = "done")),
             stop_reason = "end_turn",
             usage = list(input_tokens = 1L, output_tokens = 1L))
    }
}

local({
    captured <<- list()
    n_calls <<- 0L
    with_stubbed_post_json(loop_stub, {
        llm.api::agent(prompt = "go", provider = "anthropic",
                       system = "system text", model = "claude-test",
                       cache = "5m", verbose = FALSE, tools = list(),
                       tool_handler = function(name, args) "result")
    })
    expect_equal(n_calls, 3L)
    lens <- c(1L, 3L, 5L)        # user; +assistant,+tool_result; again
    for (k in seq_len(3L)) {
        msgs <- captured[[k]]$messages
        expect_equal(length(msgs), lens[k])
        last <- length(msgs)
        expect_equal(markers(msgs),
                     list(c(last, length(msgs[[last]]$content))))
        expect_equal(captured[[k]]$system[[1]]$cache_control$type,
                     "ephemeral")
    }
    # Request 3's tail is the second tool_result; request 2's is the first.
    expect_equal(captured[[3]]$messages[[5]]$content[[1]]$tool_use_id, "t2")
    expect_equal(captured[[2]]$messages[[3]]$content[[1]]$tool_use_id, "t1")
})

# Same loop with cache = "none": no marker anywhere, and each request's
# messages serialize identically to the plain translation of the
# history the loop had at that point.
local({
    captured <<- list()
    n_calls <<- 0L
    with_stubbed_post_json(loop_stub, {
        llm.api::agent(prompt = "go", provider = "anthropic",
                       system = "system text", model = "claude-test",
                       cache = "none", verbose = FALSE, tools = list(),
                       tool_handler = function(name, args) "result")
    })
    expect_equal(n_calls, 3L)
    for (k in seq_len(3L)) {
        expect_equal(markers(captured[[k]]$messages), list())
    }
    expect_identical(captured[[1]]$system, "system text")
    # Exact bytes for the first request, whose history we can write down.
    expect_identical(json(captured[[1]]$messages),
                     json(list(list(role = "user", content = "go"))))
})
