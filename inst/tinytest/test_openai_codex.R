# OpenAI Codex provider tests. Offline: network functions are stubbed.

ns <- asNamespace("llm.api")

b64url <- function(x) {
    x <- jsonlite::base64_enc(charToRaw(jsonlite::toJSON(x, auto_unbox = TRUE)))
    x <- sub("=+$", "", x)
    chartr("+/", "-_", x)
}

fake_codex_jwt <- function(account_id = "acct-test") {
    payload <- list(`https://api.openai.com/auth` = list(
        chatgpt_account_id = account_id
    ))
    paste("hdr", b64url(payload), "sig", sep = ".")
}

with_stubbed <- function(name, stub, expr) {
    orig <- get(name, envir = ns, inherits = FALSE)
    assignInNamespace(name, stub, ns = "llm.api")
    tryCatch(force(expr),
             finally = assignInNamespace(name, orig, ns = "llm.api"))
}

old_opts <- options(llm.api.api_base = NULL, llm.api.api_key = NULL)
on.exit(options(old_opts), add = TRUE)

old_env <- Sys.getenv(c("OPENAI_CODEX_ACCESS_TOKEN", "OPENAI_CODEX_REFRESH_TOKEN",
                        "OPENAI_CODEX_EXPIRES_AT", "OPENAI_CODEX_ACCOUNT_ID"),
                      unset = NA_character_)
on.exit({
    for (name in names(old_env)) {
        if (is.na(old_env[[name]])) {
            Sys.unsetenv(name)
        } else {
            do.call(Sys.setenv, setNames(list(old_env[[name]]), name))
        }
    }
}, add = TRUE)
Sys.unsetenv(c("OPENAI_CODEX_ACCESS_TOKEN", "OPENAI_CODEX_REFRESH_TOKEN",
               "OPENAI_CODEX_EXPIRES_AT", "OPENAI_CODEX_ACCOUNT_ID"))

# Provider config and defaults.
cfg <- llm.api:::.get_provider_config("openai_codex")
expect_equal(cfg$base_url, "https://chatgpt.com/backend-api")
expect_equal(cfg$chat_path, "/codex/responses")
expect_equal(cfg$default_model, "gpt-5.5")
expect_equal(provider_default_model("openai_codex"), "gpt-5.5")

llm_base("https://chatgpt.com/backend-api")
expect_equal(llm.api:::.detect_provider(NULL), "openai_codex")
options(llm.api.api_base = NULL)

# Credentials extract account id from a JWT-shaped access token.
creds <- openai_codex_credentials(access_token = fake_codex_jwt("acct-123"))
headers <- creds()
expect_equal(headers$Authorization, paste("Bearer", fake_codex_jwt("acct-123")))
expect_equal(headers$`chatgpt-account-id`, "acct-123")

# Responses body shape: instructions, Responses input, streaming, and tools.
body <- llm.api:::.openai_codex_body(
    messages = list(list(role = "system", content = "sys"),
                    list(role = "user", content = "hi")),
    tools = list(list(type = "function", name = "add",
                      description = "Add", parameters = list(type = "object"))),
    system = NULL,
    model = "gpt-5.5",
    reasoning_effort = "low"
)
expect_equal(body$instructions, "sys")
expect_true(body$stream)
expect_equal(body$input[[1L]]$role, "user")
expect_equal(body$input[[1L]]$content[[1L]]$type, "input_text")
expect_equal(body$tools[[1L]]$name, "add")
expect_equal(body$tool_choice, "auto")
expect_equal(body$reasoning$effort, "low")

# Streaming event merge reconstructs function-call arguments and final output.
merged <- NULL
chunks <- list(
    list(type = "response.output_item.added", output_index = 0,
         item = list(type = "function_call", id = "fc_1", call_id = "call_1",
                     name = "add", arguments = "")),
    list(type = "response.function_call_arguments.delta", output_index = 0,
         delta = "{\"a\":"),
    list(type = "response.function_call_arguments.done", output_index = 0,
         arguments = "{\"a\":1}"),
    list(type = "response.done", response = list(output = list(), usage = NULL))
)
for (chunk in chunks) {
    merged <- llm.api:::.openai_codex_merge_chunk(merged, chunk)
}
expect_equal(merged$output[[1L]]$arguments, "{\"a\":1}")

# Agent loop: first Codex response asks for a tool, second returns text.
call_count <- 0L
captured_bodies <- list()
stub_sse <- function(url, body, headers) {
    call_count <<- call_count + 1L
    captured_bodies[[call_count]] <<- body
    if (call_count == 1L) {
        list(
             output = list(list(type = "function_call", id = "fc_1",
                                call_id = "call_1", name = "add",
                                arguments = "{\"a\":6,\"b\":7}")),
             usage = list(input_tokens = 10L, output_tokens = 5L,
                          input_tokens_details = list(cached_tokens = 0L))
        )
    } else {
        list(
             output = list(list(type = "message", content = list(
                 list(type = "output_text", text = "tool sum is 13")
             ))),
             usage = list(input_tokens = 20L, output_tokens = 3L,
                          input_tokens_details = list(cached_tokens = 0L))
        )
    }
}

local({
    tool_calls <- 0L
    result <- with_stubbed(".openai_codex_post_sse", stub_sse, {
        llm.api::agent(
            "add numbers",
            provider = "openai_codex",
            model = "gpt-5.5",
            credentials = creds,
            tools = list(list(name = "add", description = "Add",
                              input_schema = list(type = "object"))),
            tool_handler = function(name, args) {
                tool_calls <<- tool_calls + 1L
                as.character(args$a + args$b)
            },
            verbose = FALSE
        )
    })
    expect_equal(result$content, "tool sum is 13")
    expect_equal(tool_calls, 1L)
    expect_equal(call_count, 2L)
    expect_equal(captured_bodies[[2L]]$input[[3L]]$type, "function_call_output")
    expect_equal(captured_bodies[[2L]]$input[[3L]]$call_id, "call_1")
    expect_true(result$usage$cost > 0)
})

# chat() dispatches to the Codex helper and attaches cost.
chat_stub <- function(body, config, stream) {
    list(content = "ok", thinking = NULL, finish_reason = NULL,
         usage = list(prompt_tokens = 10L, completion_tokens = 2L,
                      prompt_tokens_details = list(cached_tokens = 0L)))
}
local({
    result <- with_stubbed(".chat_openai_codex", chat_stub, {
        llm.api::chat("hi", provider = "openai_codex", model = "gpt-5.5",
                      credentials = creds)
    })
    expect_equal(result$content, "ok")
    expect_true(result$usage$cost > 0)
})
