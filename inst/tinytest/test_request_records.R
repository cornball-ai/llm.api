# Real agent/chat adapters and real SSE parsers, with only HTTP I/O faked.
local({
    saved <- list()
    replace <- function(package, name, fn) {
        key <- paste(package, name)
        saved[[key]] <<- list(package = package, name = name,
            fn = get(name, asNamespace(package)))
        utils::assignInNamespace(name, fn, package)
    }
    on.exit(for (item in saved) utils::assignInNamespace(item$name, item$fn, item$package), add = TRUE)
    runtime <- llm.api:::.request_runtime
    previous <- runtime$current
    previous_notice <- runtime$notice
    on.exit(runtime$current <- previous, add = TRUE)
    on.exit(runtime$notice <- previous_notice, add = TRUE)
    opt <- options(llm.api.transport_wait = 0)
    on.exit(options(opt), add = TRUE)
    replace("llm.api", ".get_provider_config", function(provider) list(
        provider = provider, api_key = "fixture-auth-secret", default_model = "fixture-model",
        base_url = "https://example.invalid", chat_path = "/fixture",
        credentials = if (provider %in% c("anthropic_claude", "openai_codex"))
            function() c(Authorization = "Bearer fixture-auth-secret")))
    payload <- NULL
    request_count <- 0L
    mode <- "normal"
    requests <- list()
    stream_data <- NULL
    wire <- NULL
    setopt <- curl::handle_setopt
    replace("curl", "handle_setopt", function(handle, ..., .list = list()) {
        args <- c(list(...), .list)
        if (!is.null(args$postfields)) {
            payload <<- as.character(args$postfields)
            requests[[length(requests) + 1L]] <<- payload
        }
        setopt(handle, ..., .list = .list)
    })
    headers <- charToRaw(paste0("HTTP/1.1 200 OK\r\nx-request-id: fixture-request\r\n",
        "Set-Cookie: do-not-record\r\nAuthorization: do-not-record\r\n\r\n"))
    reply <- function() {
        provider <- runtime$current$provider
        anthropic <- provider %in% c("anthropic", "anthropic_claude")
        if (mode == "tool" && request_count == 1L) {
            return(list(id = "chatcmpl_tool", model = "served-model",
                choices = list(list(message = list(role = "assistant", content = NULL,
                    tool_calls = list(list(id = "call_fixture", type = "function",
                        `function` = list(name = "fixture", arguments = "{}")))), finish_reason = "tool_calls")),
                usage = list(prompt_tokens = 7L, completion_tokens = 3L, total_tokens = 10L)))
        }
        if (anthropic) list(id = "msg_fixture", model = "served-model",
            content = list(list(type = "text", text = "done")), stop_reason = "end_turn",
            usage = list(input_tokens = 7L, output_tokens = 3L, cache_read_input_tokens = 2L)) else
            list(id = "chatcmpl_fixture", model = "served-model",
                choices = list(list(message = list(role = "assistant", content = "done"), finish_reason = "stop")),
                usage = list(prompt_tokens = 7L, completion_tokens = 3L, total_tokens = 10L))
    }
    transport_error <- structure(list(message = "Timeout was reached", call = NULL),
        class = c("curl_error_operation_timedout", "curl_error", "error", "condition"))
    preflight <- function() {
        request_count <<- request_count + 1L
        if (mode == "retry" && request_count == 1L) stop(transport_error)
    }
    replace("curl", "curl_fetch_memory", function(url, handle) {
        preflight()
        list(status_code = if (mode == "http-error") 429L else 200L, headers = headers,
            content = charToRaw(if (mode == "bad-json") "{" else
                as.character(jsonlite::toJSON(reply(), auto_unbox = TRUE, null = "null"))))
    })
    emit <- function(fun, object) fun(charToRaw(paste0("data: ",
        jsonlite::toJSON(object, auto_unbox = TRUE, null = "null"), "\n\n")))
    replace("curl", "curl_fetch_stream", function(url, fun, handle) {
        preflight()
        body <- jsonlite::fromJSON(payload, simplifyVector = FALSE)
        if (!is.null(body$input)) {
            wire <<- "responses"
            emit(fun, list(type = "response.created", response = list(id = "resp_fixture",
                model = "served-model", output = list())))
            emit(fun, list(type = "response.output_text.delta", delta = "done"))
            emit(fun, list(type = "response.completed", response = list(id = "resp_fixture",
                model = "served-model", status = "completed",
                output = list(list(type = "message", content = list(list(type = "output_text", text = "done")))),
                usage = list(input_tokens = 7L, output_tokens = 3L))))
        } else if (runtime$current$provider %in% c("anthropic", "anthropic_claude")) {
            wire <<- "messages"
            emit(fun, list(type = "message_start", message = list(id = "msg_fixture",
                model = "served-model", usage = list(input_tokens = 7L, output_tokens = 0L))))
            if (mode == "partial-error") stop(transport_error)
            emit(fun, list(type = "content_block_start", index = 0L,
                content_block = list(type = "text", text = "")))
            emit(fun, list(type = "content_block_delta", index = 0L,
                delta = list(type = "text_delta", text = "done")))
            emit(fun, list(type = "message_delta", delta = list(stop_reason = "end_turn"),
                usage = list(output_tokens = 3L)))
        } else {
            wire <<- "chat_completions"
            emit(fun, list(id = "chatcmpl_fixture", model = "served-model",
                choices = list(list(delta = list(content = "done"), finish_reason = "stop"))))
            emit(fun, list(id = "chatcmpl_fixture", model = "served-model", choices = list(),
                usage = list(prompt_tokens = 7L, completion_tokens = 3L, total_tokens = 10L)))
        }
        list(status_code = 200L, headers = headers)
    })
    events <- list()
    observe <- function(event) events[[length(events) + 1L]] <<- event
    reset <- function() {
        events <<- list()
        request_count <<- 0L
        requests <<- list()
    }
    had_seed <- exists(".Random.seed", .GlobalEnv, inherits = FALSE)
    seed <- if (had_seed) get(".Random.seed", .GlobalEnv)
    providers <- c("anthropic", "anthropic_claude", "openai", "moonshot", "ollama",
        "openai_compatible", "openai_codex")
    for (provider in providers) {
        for (surface in c("agent", "chat")) {
            reset()
            args <- list(prompt = "fixture prompt", provider = provider, model = "fixture-model",
                request_callback = observe)
            if (surface == "agent") args$verbose <- FALSE
            result <- do.call(getExportedValue("llm.api", surface), args)
            expect_identical(result$content, "done")
            expect_equal(request_count, 1L)
            expect_identical(vapply(events, `[[`, "", "phase"), c("start", "end"))
            expect_identical(events[[1L]]$serialized_request, requests[[1L]])
            expect_identical(events[[2L]]$provider, provider)
            expect_identical(events[[2L]]$requested_model, "fixture-model")
            expect_identical(events[[2L]]$reported_model, "served-model")
            expect_true(nzchar(events[[2L]]$response_id))
            expect_true(length(events[[2L]]$raw_usage) > 0L)
            expect_identical(events[[2L]]$request_headers, list(`x-request-id` = "fixture-request"))
            expect_false(grepl("fixture-auth-secret|do-not-record", jsonlite::toJSON(events)))
        }
    }
    expect_identical(exists(".Random.seed", .GlobalEnv, inherits = FALSE), had_seed)
    if (had_seed) expect_identical(get(".Random.seed", .GlobalEnv), seed)
    expect_identical(runtime$current, previous)

    for (provider in c("openai", "moonshot", "ollama", "openai_compatible")) {
        reset()
        deltas <- character()
        llm.api::agent("fixture", provider = provider, model = "fixture-model", verbose = FALSE,
            request_callback = observe, on_delta = function(x) deltas <<- c(deltas, x))
        expect_identical(deltas, "done")
        expect_identical(events[[2L]]$wire, "chat_completions")
        expect_equal(events[[2L]]$raw_usage$completion_tokens, 3L)
        expect_true(jsonlite::fromJSON(events[[1L]]$serialized_request)$stream_options$include_usage)
    }
    reset()
    llm.api::agent("fixture", provider = "openai", model = "fixture-model", verbose = FALSE,
        web_search = TRUE, request_callback = observe)
    expect_identical(events[[2L]]$wire, "responses")
    expect_identical(events[[2L]]$provider, "openai")
    reset()
    mode <- "tool"
    handled <- 0L
    result <- llm.api::agent("fixture", provider = "openai", model = "fixture-model", verbose = FALSE,
        tools = list(list(name = "fixture", description = "fixture", input_schema = list(type = "object"))),
        tool_handler = function(name, args) { handled <<- handled + 1L; "fixture result" },
        request_callback = observe)
    expect_equal(handled, 1L)
    expect_equal(result$usage$total_tokens, 20)
    expect_length(events, 4L)
    expect_length(unique(vapply(events, `[[`, "", "request_id")), 2L)
    expect_true(grepl("fixture result", events[[3L]]$serialized_request, fixed = TRUE))
    expect_identical(events[[4L]]$stop_reason, "stop")

    # A hidden transport retry has one logical ID and two attempt IDs.
    reset()
    mode <- "retry"
    llm.api::agent("fixture", provider = "openai", model = "fixture-model",
        verbose = FALSE, request_callback = observe)
    expect_equal(request_count, 2L)
    expect_identical(vapply(events, `[[`, "", "phase"), c("start", "error", "start", "end"))
    expect_length(unique(vapply(events, `[[`, "", "request_id")), 1L)
    expect_length(unique(vapply(events, `[[`, "", "attempt_id")), 2L)
    expect_inherits(structure(list(), class = unlist(events[[2L]]$condition_classes)), "curl_error")

    # No retry after streaming bytes arrive, and usage from those bytes survives.
    reset()
    mode <- "partial-error"
    expect_error(llm.api::agent("fixture", provider = "anthropic", model = "fixture-model",
        verbose = FALSE, request_callback = observe), "Timeout")
    expect_equal(request_count, 1L)
    expect_equal(events[[2L]]$raw_usage$input_tokens, 7L)
    expect_identical(events[[2L]]$response_id, "msg_fixture")

    reset()
    mode <- "normal"
    result <- llm.api::agent("fixture", provider = "anthropic", model = "fixture-model",
        verbose = FALSE, request_callback = observe, on_delta = function(x) llm.api::llm_cancel())
    expect_identical(events[[2L]]$status, "cancelled")
    expect_true(events[[2L]]$cancelled)
    expect_equal(events[[2L]]$raw_usage$input_tokens, 7L)
    expect_equal(request_count, 1L)

    # Observer failures cannot be mistaken for network failures/retries.
    reset()
    suppressMessages(llm.api::agent("fixture", provider = "openai", model = "fixture-model",
        verbose = FALSE, request_callback = function(e) stop(transport_error)))
    expect_equal(request_count, 1L)
    for (error_mode in c("http-error", "bad-json")) {
        reset()
        mode <- error_mode
        expect_error(llm.api::chat("fixture", provider = "openai", model = "fixture-model",
            request_callback = observe))
        expect_identical(events[[2L]]$phase, "error")
        expect_equal(request_count, 1L)
    }
})
