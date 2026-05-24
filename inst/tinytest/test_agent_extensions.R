# Tests for the 0.1.4 additions:
#  - Anthropic cache_control on system message
#  - Anthropic thinking_budget_tokens (validation + body shape)
#  - OpenAI max_tokens -> max_completion_tokens rename (NOT Moonshot)
#
# `agent()` uses .post_json which we can stub cleanly; `chat()` uses
# curl::curl_fetch_memory directly so we test those code paths via
# the extracted body-builder helpers (.anthropic_system_with_cache,
# .validate_thinking_budget) and lean on agent() for integration
# coverage of the same logic.

ns <- asNamespace("llm.api")
orig_post_json <- get(".post_json", envir = ns, inherits = FALSE)

with_stubbed_post_json <- function(stub, expr) {
    assignInNamespace(".post_json", stub, ns = "llm.api")
    tryCatch(force(expr),
             finally = assignInNamespace(".post_json", orig_post_json,
                                         ns = "llm.api"))
}

# --- .anthropic_system_with_cache helper ----------------------------

# cache = "none" returns the system text unchanged.
expect_equal(llm.api:::.anthropic_system_with_cache("be helpful", "none"),
             "be helpful")

# cache = "5m" wraps in a single text block with ephemeral cache_control
# and no ttl (5min is Anthropic's default ephemeral TTL).
local({
    out <- llm.api:::.anthropic_system_with_cache("be helpful", "5m")
    expect_true(is.list(out))
    expect_equal(length(out), 1L)
    expect_equal(out[[1L]]$type, "text")
    expect_equal(out[[1L]]$text, "be helpful")
    expect_equal(out[[1L]]$cache_control$type, "ephemeral")
    expect_null(out[[1L]]$cache_control$ttl)
})

# cache = "1h" sets ttl = "1h" on the cache_control block.
local({
    out <- llm.api:::.anthropic_system_with_cache("be helpful", "1h")
    expect_equal(out[[1L]]$cache_control$type, "ephemeral")
    expect_equal(out[[1L]]$cache_control$ttl, "1h")
})

# --- .validate_thinking_budget --------------------------------------

# Must be a positive integer.
expect_error(llm.api:::.validate_thinking_budget("not a number"),
             pattern = "must be a single integer")
expect_error(llm.api:::.validate_thinking_budget(c(1024L, 2048L)),
             pattern = "must be a single integer")
expect_error(llm.api:::.validate_thinking_budget(NA),
             pattern = "must be a single integer")
expect_error(llm.api:::.validate_thinking_budget(1500.5),
             pattern = "must be a single integer")

# Must be at least 1024 (Anthropic's minimum).
expect_error(llm.api:::.validate_thinking_budget(512L),
             pattern = "at least 1024")

# Budget must leave room for the completion.
expect_error(
             llm.api:::.validate_thinking_budget(8000L, max_tokens = 8000L),
             pattern = "strictly less than .max_tokens."
)
expect_error(
             llm.api:::.validate_thinking_budget(8000L, max_tokens = 4000L),
             pattern = "strictly less than .max_tokens."
)

# Valid input -> invisible TRUE.
expect_true(llm.api:::.validate_thinking_budget(2048L, max_tokens = 8000L))
expect_true(llm.api:::.validate_thinking_budget(2048L, max_tokens = NULL))

# --- chat() rejects Anthropic-only features on other providers ------

# chat(provider = "openai", cache = "5m") warns and downgrades to none.
# We don't need to make the request succeed; we just want to catch
# the warning.
local({
    expect_warning(
        out <- tryCatch(
                        llm.api::chat(prompt = "x", provider = "openai",
                                      cache = "5m"),
                        error = function(e) NULL
        ),
        pattern = "cache.*Anthropic-only"
    )
})

# chat(provider = "openai", thinking_budget_tokens = 2048) warns and
# drops the param.
local({
    expect_warning(
        out <- tryCatch(
                        llm.api::chat(prompt = "x", provider = "openai",
                                      max_tokens = 8000L,
                                      thinking_budget_tokens = 2048L),
                        error = function(e) NULL
        ),
        pattern = "thinking_budget_tokens.*Anthropic-only"
    )
})

# --- agent() Anthropic with cache + thinking_budget_tokens ----------

# agent() integration: cache and thinking_budget_tokens make it into
# the body Anthropic sees. Uses the .post_json stub.
anth_agent_capture <- NULL
anth_agent_stub <- function(url, body, headers) {
    anth_agent_capture <<- body
    list(
         content = list(list(type = "text", text = "done")),
         usage = list(input_tokens = 1L, output_tokens = 1L)
    )
}

local({
    anth_agent_capture <<- NULL
    with_stubbed_post_json(anth_agent_stub, {
        llm.api::agent(prompt = "go",
                       provider = "anthropic",
                       system = "system text",
                       model = "claude-test",
                       cache = "5m",
                       thinking_budget_tokens = 2048L,
                       verbose = FALSE,
                       tools = list())
    })
    expect_true(is.list(anth_agent_capture$system))
    expect_equal(anth_agent_capture$system[[1L]]$cache_control$type,
                 "ephemeral")
    expect_equal(anth_agent_capture$thinking$type, "enabled")
    expect_equal(anth_agent_capture$thinking$budget_tokens, 2048L)
})

# agent() with cache = "1h" sets the longer TTL.
local({
    anth_agent_capture <<- NULL
    with_stubbed_post_json(anth_agent_stub, {
        llm.api::agent(prompt = "go",
                       provider = "anthropic",
                       system = "system text",
                       model = "claude-test",
                       cache = "1h",
                       verbose = FALSE,
                       tools = list())
    })
    expect_equal(anth_agent_capture$system[[1L]]$cache_control$ttl, "1h")
})

# agent() default: no cache, no thinking -- system stays as plain text.
local({
    anth_agent_capture <<- NULL
    with_stubbed_post_json(anth_agent_stub, {
        llm.api::agent(prompt = "go",
                       provider = "anthropic",
                       system = "system text",
                       model = "claude-test",
                       verbose = FALSE,
                       tools = list())
    })
    expect_equal(anth_agent_capture$system, "system text")
    expect_null(anth_agent_capture$thinking)
})

# --- agent() OpenAI max_tokens rename via ... ----------------------

# Capture the body that .agent_openai sends; verify max_tokens
# becomes max_completion_tokens for openai and stays as max_tokens
# for moonshot.
openai_capture_body <- NULL
openai_capture_stub <- function(url, body, headers) {
    openai_capture_body <<- body
    list(
         choices = list(list(
                             message = list(role = "assistant", content = "done",
                                            tool_calls = NULL),
                             finish_reason = "stop"
        )),
         usage = list(prompt_tokens = 1L, completion_tokens = 1L)
    )
}

# OpenAI: max_tokens via ... gets renamed to max_completion_tokens.
local({
    openai_capture_body <<- NULL
    with_stubbed_post_json(openai_capture_stub, {
        llm.api::agent(prompt = "go",
                       provider = "openai",
                       model = "gpt-4o",
                       verbose = FALSE,
                       max_tokens = 200L)
    })
    expect_null(openai_capture_body$max_tokens)
    expect_equal(openai_capture_body$max_completion_tokens, 200L)
})

# Moonshot: max_tokens via ... stays as max_tokens.
local({
    openai_capture_body <<- NULL
    with_stubbed_post_json(openai_capture_stub, {
        llm.api::agent(prompt = "go",
                       provider = "moonshot",
                       model = "kimi-k2",
                       verbose = FALSE,
                       max_tokens = 200L)
    })
    expect_equal(openai_capture_body$max_tokens, 200L)
    expect_null(openai_capture_body$max_completion_tokens)
})

# OpenAI: caller-provided max_completion_tokens takes precedence;
# max_tokens is left for the caller to disambiguate. The rename is
# gated on is.null(b$max_completion_tokens).
local({
    openai_capture_body <<- NULL
    with_stubbed_post_json(openai_capture_stub, {
        llm.api::agent(prompt = "go",
                       provider = "openai",
                       model = "gpt-4o",
                       verbose = FALSE,
                       max_completion_tokens = 500L,
                       max_tokens = 200L)
    })
    expect_equal(openai_capture_body$max_completion_tokens, 500L)
})
