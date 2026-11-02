# Google (Gemini) through its OpenAI-compatible endpoint. The provider
# rides the openai wire, so these pin the routing, the endpoint, the
# default model, and the one Gemini-specific requirement: a tool call's
# thought signature (`extra_content`) goes back verbatim on the next
# request.
#
# Fixture options are set inside each local() block. A top-level
# on.exit() in a tinytest file runs right away, not when the file ends,
# so a top-level options()/on.exit() pair leaves nothing in effect and
# the real key from the environment gets used instead.

ns <- asNamespace("llm.api")
with_stubbed <- function(name, stub, expr) {
    orig <- get(name, envir = ns, inherits = FALSE)
    assignInNamespace(name, stub, ns = "llm.api")
    on.exit(assignInNamespace(name, orig, ns = "llm.api"), add = TRUE)
    force(expr)
}
fixture_options <- function() {
    options(llm.api_base = NULL, llm.api_key = "fixture-key",
            llm.api.api_base = NULL, llm.api.api_key = NULL)
}

google_base <- "https://generativelanguage.googleapis.com/v1beta/openai"

# --- agent(): openai wire, Gemini endpoint, default model, signature echoed ---

local({
    opts <- fixture_options()
    on.exit(options(opts), add = TRUE)
    seen <- list()
    replies <- list(
        list(choices = list(list(
            message = list(role = "assistant", content = NULL,
                           tool_calls = list(list(
                               id = "call_1", type = "function",
                               `function` = list(name = "get_weather",
                                                 arguments = '{"city":"Chicago"}'),
                               extra_content = list(google = list(
                                   thought_signature = "sig"))))),
            finish_reason = "tool_calls")),
            usage = list(prompt_tokens = 10L, completion_tokens = 5L)),
        list(choices = list(list(
            message = list(role = "assistant", content = "Overcast."),
            finish_reason = "stop")),
            usage = list(prompt_tokens = 20L, completion_tokens = 3L)))

    res <- with_stubbed(".post_json", function(url, body, headers) {
        seen[[length(seen) + 1L]] <<- list(url = url, body = body,
                                           headers = headers)
        replies[[length(seen)]]
    }, agent("Weather in Chicago?",
             tools = list(list(
                 name = "get_weather", description = "Weather",
                 input_schema = list(type = "object",
                                     properties = list(city = list(type = "string"))))),
             tool_handler = function(name, args) "17C, overcast",
             provider = "google", verbose = FALSE))

    expect_identical(res$content, "Overcast.")
    expect_identical(res$provider, "google")
    # No model given: the provider default is sent, not NULL (which the
    # endpoint rejects with "model is not specified").
    expect_identical(res$model, "gemini-3.5-flash")
    expect_identical(seen[[1L]]$body$model, "gemini-3.5-flash")
    expect_identical(length(seen), 2L)
    expect_identical(seen[[1L]]$url, paste0(google_base, "/chat/completions"))
    # Compared with identical() so a failure prints TRUE/FALSE, never a
    # bearer token.
    expect_true(identical(unname(seen[[1L]]$headers[["Authorization"]]),
                          "Bearer fixture-key"))
    # Tools in chat-completions shape, not Claude's.
    expect_identical(seen[[1L]]$body$tools[[1L]]$type, "function")
    expect_identical(seen[[1L]]$body$tools[[1L]][["function"]]$name,
                     "get_weather")
    # The second request carries the assistant message unchanged,
    # thought signature included, then the tool result.
    msgs <- seen[[2L]]$body$messages
    expect_identical(msgs[[2L]]$tool_calls[[1L]]$extra_content,
                     list(google = list(thought_signature = "sig")))
    expect_identical(msgs[[3L]]$role, "tool")
    expect_identical(msgs[[3L]]$tool_call_id, "call_1")
})

# --- chat(): compat chat path with the google config and default model ---

local({
    opts <- fixture_options()
    on.exit(options(opts), add = TRUE)
    seen <- NULL
    res <- with_stubbed(".chat_openai_compatible", function(body, config, stream) {
        seen <<- list(body = body, config = config)
        list(content = "PONG", finish_reason = "stop")
    }, chat("ping", provider = "google"))
    expect_identical(res$content, "PONG")
    expect_identical(res$model, "gemini-3.5-flash")
    expect_identical(seen$config$provider, "google")
    expect_identical(seen$config$base_url, google_base)
    expect_true(identical(seen$config$api_key, "fixture-key"))
    expect_identical(seen$body$model, "gemini-3.5-flash")
})

# A gemini-* model id auto-detects the provider.
local({
    opts <- fixture_options()
    on.exit(options(opts), add = TRUE)
    seen <- NULL
    with_stubbed(".chat_openai_compatible", function(body, config, stream) {
        seen <<- config
        list(content = "", finish_reason = "stop")
    }, chat("ping", model = "gemini-3.5-flash"))
    expect_identical(seen$provider, "google")
})

# Google Search grounding is not accepted on the compat endpoint, so
# web_search warns and is dropped like any unsupported provider.
local({
    opts <- fixture_options()
    on.exit(options(opts), add = TRUE)
    seen <- NULL
    expect_warning(
        with_stubbed(".chat_openai_compatible", function(body, config, stream) {
            seen <<- body
            list(content = "", finish_reason = "stop")
        }, chat("ping", provider = "google", web_search = TRUE)),
        pattern = "web_search")
    expect_null(seen$web_search)
})
