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
