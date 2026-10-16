# The transport is fake, but conversion, parsing, dispatch, checkpointing,
# history replay, and usage accounting are the real agent loop.
local({
    ns <- asNamespace("llm.api")
    for (model in c("gpt-6-astra", "gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna")) {
        expect_true(ns$.openai_requires_responses_tools(model))
    }
    for (model in c("gpt-4o", "gpt-5.5", "gpt-5.6-sol", "other-model")) {
        expect_false(ns$.openai_requires_responses_tools(model))
    }
    for (content in list(NULL, "")) {
        converted <- ns$.openai_codex_messages_to_input(list(
            list(role = "assistant", content = content, tool_calls = list(
                list(id = "no_text", type = "function", `function` = list(
                    name = "lookup", arguments = "{}")))),
            list(role = "tool", tool_call_id = "no_text", content = "done")))
        expect_equal(vapply(converted, function(x) x$type, character(1)),
                     c("function_call", "function_call_output"))
        expect_equal(vapply(converted, function(x) x$call_id, character(1)),
                     c("no_text", "no_text"))
    }
    original <- ns$.openai_codex_post_sse
    old_cc <- ns$.agent_openai
    opts <- options(llm.api_base = NULL, llm.api.api_base = NULL,
                    llm.api_key = "fixture-key")
    on.exit({
        options(opts)
        assignInNamespace(".openai_codex_post_sse", original, "llm.api")
        assignInNamespace(".agent_openai", old_cc, "llm.api")
    }, add = TRUE)
    assignInNamespace(".agent_openai", function(...) {
        stop("tool request reached Chat Completions")
    }, "llm.api")
    for (provider in c("openai", "openai_codex")) {
        seen <- list()
        dispatched <- 0L
        checkpoints <- 0L
        snapshots <- list()
        assignInNamespace(".openai_codex_post_sse", function(url, body, headers, on_delta = NULL) {
            seen[[length(seen) + 1L]] <<- list(url = url, body = body, headers = headers)
            output <- if (length(seen) == 1L) list(
                list(type = "reasoning", id = "rs_fixture", encrypted_content = "opaque", summary = list()),
                list(type = "function_call", id = "fc_fixture", call_id = "call_fixture",
                     name = "lookup", arguments = '{"key":"example"}')) else list(
                list(type = "message", role = "assistant", content = list(
                    list(type = "output_text", text = "found example"))))
            list(status = "completed", output = output,
                 usage = list(input_tokens = 10L, output_tokens = 3L))
        }, "llm.api")
        args <- list(prompt = "Look up example", provider = provider,
                     model = "gpt-6-astra", web_search = FALSE,
                     reasoning_effort = "high", verbose = FALSE,
                     tools = list(list(name = "lookup", description = "Look up a key",
                         input_schema = list(type = "object", properties = list(
                             key = list(type = "string")), required = list("key")))),
                     tool_handler = function(name, args, context) {
                         dispatched <<- dispatched + 1L
                         expect_equal(name, "lookup")
                         expect_equal(args$key, "example")
                         expect_equal(context$provider, provider)
                         "fixture result"
                     }, history_callback = function(history) {
                         snapshots[[length(snapshots) + 1L]] <<- history
                     }, checkpoint_callback = function(history, context) {
                         checkpoints <<- checkpoints + 1L
                         expect_true(ns$.openai_responses_history(history))
                         NULL
                     })
        if (provider == "openai_codex") {
            args$credentials <- function() {
                list(Authorization = "Bearer fixture-codex", `chatgpt-account-id` = "fixture-account")
            }
        } else {
            args$max_completion_tokens <- 1000L
        }
        # Selecting GPT-6 in an existing conversation also changes the wire.
        # Preserve earlier Chat Completions calls/results, including batches.
        args$history <- list(
            list(role = "user", content = "Earlier lookup"),
            list(role = "assistant", content = "Checking both keys", tool_calls = list(
                list(id = "old_a", type = "function", `function` = list(
                    name = "lookup", arguments = '{"key":"a"}')),
                list(id = "old_b", type = "function", `function` = list(
                    name = "lookup", arguments = '{"key":"b"}')))),
            list(role = "tool", tool_call_id = "old_a", content = "result a"),
            list(role = "tool", tool_call_id = "old_b", content = "result b"))
        result <- do.call(llm.api::agent, args)
        expect_equal(length(seen), 2L)
        expect_equal(dispatched, 1L)
        expect_equal(checkpoints, 1L)
        expect_equal(length(snapshots), 3L)
        snap_results <- Filter(function(x) identical(x$type, "function_call_output"), snapshots[[2]])
        expect_equal(length(snap_results), 1L)
        expect_equal(snap_results[[1]]$call_id, "call_fixture")
        expect_equal(result$content, "found example")
        expect_equal(result$usage$input_tokens, 20L)
        expected <- if (provider == "openai") "https://api.openai.com/v1/responses" else
            "https://chatgpt.com/backend-api/codex/responses"
        expect_equal(seen[[1]]$url, expected)
        first_input <- seen[[1]]$body$input
        old_calls <- Filter(function(x) identical(x$type, "function_call"), first_input)
        expect_equal(length(old_calls), 2L)
        expect_equal(vapply(old_calls, function(x) x$call_id, character(1)), c("old_a", "old_b"))
        expect_equal(vapply(old_calls, function(x) x$arguments, character(1)),
                     c('{"key":"a"}', '{"key":"b"}'))
        old_results <- Filter(function(x) identical(x$type, "function_call_output"), first_input)
        expect_equal(vapply(old_results, function(x) x$call_id, character(1)), c("old_a", "old_b"))
        expect_equal(vapply(old_results, function(x) x$output, character(1)), c("result a", "result b"))
        expect_false(any(vapply(first_input, function(x) identical(x$role, "tool"), logical(1))))
        expect_equal(first_input[[2]]$content[[1]]$text, "Checking both keys")
        if (provider == "openai") {
            expect_equal(seen[[1]]$body$max_output_tokens, 1000L)
            expect_null(seen[[1]]$body$max_completion_tokens)
        }
        for (request in seen) {
            expect_equal(request$body$reasoning$effort, "high")
            expect_false(any(vapply(request$body$tools, function(x) identical(x$type, "web_search"), logical(1))))
            expect_equal(request$body$tools[[1]]$name, "lookup")
            expect_null(request$body$tools[[1]]$`function`)
        }
        returned <- Filter(function(x) identical(x$type, "function_call_output") &&
            identical(x$call_id, "call_fixture"), seen[[2]]$body$input)
        expect_equal(length(returned), 1L)
        expect_equal(returned[[1]]$call_id, "call_fixture")
        expect_equal(returned[[1]]$output, "fixture result")
        reasoning <- Filter(function(x) identical(x$type, "reasoning"), seen[[2]]$body$input)
        expect_equal(reasoning[[1]]$encrypted_content, "opaque")
        # Dropping the tool list on a later request must not change the wire.
        args$prompt <- "Continue without tools"
        args$history <- result$history
        args$tools <- list()
        args$tool_handler <- NULL
        do.call(llm.api::agent, args)
        expect_equal(length(seen), 3L)
        expect_equal(seen[[3]]$url, expected)
    }
})
