# Streaming over the Chat Completions wire: openai, moonshot, ollama,
# and any openai_compatible gateway.
#
# The return is shaped exactly like a non-streamed response -- one
# choices[[1]]$message with content and tool_calls, plus usage -- so
# every caller parses one shape and the streamed and non-streamed paths
# can be compared with identical(). Anything else makes the equivalence
# test unwritable, and that test is the only thing standing between a
# tool-call reassembly bug and a turn that runs the wrong tool.

# Merge one tool-call fragment into the accumulator.
#
# Arguments arrive as string pieces across many chunks and are spliced
# back together; `id` and `name` arrive once, usually on the first
# fragment for that index. Keyed by the wire's own `index` rather than
# by arrival order, because a provider emitting two calls interleaves
# their fragments and appending in arrival order would braid them into
# each other -- producing valid JSON that calls the wrong tool.
.llm_cc_merge_tool_call <- function(calls, tc) {
    key <- as.character((tc$index %||% 0L) + 1L)
    cur <- calls[[key]] %||% list(id = NULL, type = "function",
                                  `function` = list(name = NULL, arguments = ""))
    if (!is.null(tc$id)) {
        cur$id <- tc$id
    }
    if (!is.null(tc$type)) {
        cur$type <- tc$type
    }
    fn <- tc[["function"]]
    if (!is.null(fn$name)) {
        cur[["function"]]$name <- fn$name
    }
    if (!is.null(fn$arguments)) {
        cur[["function"]]$arguments <- paste0(
            cur[["function"]]$arguments %||% "", fn$arguments)
    }
    calls[[key]] <- cur
    calls
}

# The accumulated calls, in the wire's index order, as the
# non-streamed shape.
.llm_cc_tool_calls <- function(calls) {
    if (!length(calls)) {
        return(NULL)
    }
    unname(calls[order(as.integer(names(calls)))])
}

# POST a chat-completions request and read the SSE stream back.
#
# stream_options$include_usage asks for the token counts on the final
# chunk. Without it a streamed request reports no usage at all and
# every cost figure downstream silently becomes zero -- which looks
# exactly like a free model rather than like a missing field.
.openai_cc_post_sse <- function(url, body, headers, on_delta = NULL) {
    .llm_assert_translated(body$messages, "the request body")
    body$stream <- TRUE
    body$stream_options <- body$stream_options %||% list(include_usage = TRUE)

    h <- curl::new_handle()
    curl::handle_setopt(h, customrequest = "POST",
                        postfields = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"))
    curl::handle_setheaders(h, .list = as.list(headers))

    content <- ""
    reasoning <- ""
    role <- "assistant"
    finish_reason <- NULL
    usage <- NULL
    calls <- list()
    buffer <- ""
    raw_text <- ""

    callback <- function(data) {
        text <- rawToChar(data)
        raw_text <<- paste0(raw_text, text)
        buffer <<- paste0(buffer, text)
        lines <- strsplit(buffer, "\n", fixed = TRUE)[[1L]]
        # A chunk can split a line in half. Whatever follows the last
        # newline is an unfinished line and waits for the next chunk.
        if (!endsWith(buffer, "\n")) {
            buffer <<- lines[[length(lines)]]
            lines <- lines[-length(lines)]
        } else {
            buffer <<- ""
        }
        for (line in lines) {
            line <- trimws(line)
            if (!startsWith(line, "data: ") ||
                identical(line, "data: [DONE]")) {
                next
            }
            chunk <- tryCatch(
                              jsonlite::fromJSON(substring(line, 7L), simplifyVector = FALSE),
                              error = function(e) NULL)
            if (is.null(chunk)) {
                next
            }
            if (!is.null(chunk$usage)) {
                usage <<- chunk$usage
            }
            # The usage-only final chunk carries no choices at all.
            if (!length(chunk$choices)) {
                next
            }
            choice <- chunk$choices[[1L]]
            if (!is.null(choice$finish_reason)) {
                finish_reason <<- choice$finish_reason
            }
            delta <- choice$delta
            if (is.null(delta)) {
                next
            }
            if (!is.null(delta$role)) {
                role <<- delta$role
            }
            if (!is.null(delta$content)) {
                content <<- paste0(content, delta$content)
                .llm_emit_delta(on_delta, delta$content)
            }
            think <- delta$reasoning_content %||% delta$reasoning
            if (!is.null(think)) {
                reasoning <<- paste0(reasoning, think)
            }
            for (tc in delta$tool_calls %||% list()) {
                calls <<- .llm_cc_merge_tool_call(calls, tc)
            }
        }
        length(data)
    }

    assemble <- function() {
        msg <- list(role = role,
                    # NULL rather than "" when empty, which is what the
                    # non-streamed wire sends alongside a tool call.
                    content = if (nzchar(content)) content else NULL)
        tcs <- .llm_cc_tool_calls(calls)
        if (!is.null(tcs)) {
            msg$tool_calls <- tcs
        }
        if (nzchar(reasoning)) {
            msg$reasoning_content <- reasoning
        }
        list(choices = list(list(message = msg, finish_reason = finish_reason)),
             usage = usage)
    }

    fetched <- .llm_with_cancel(curl::curl_fetch_stream(url, callback,
            handle = h))
    if (fetched$cancelled) {
        partial <- assemble()
        attr(partial, "llm_cancelled") <- TRUE
        return(partial)
    }
    resp <- fetched$value
    if (resp$status_code >= 400) {
        # The error body arrived down the same stream, so it is in
        # raw_text rather than anywhere curl kept it.
        err <- tryCatch(jsonlite::fromJSON(raw_text, simplifyVector = FALSE),
                        error = function(e) NULL)
        stop("API error (", resp$status_code, "): ",
             err$error$message %||% raw_text %||% "Unknown error",
             call. = FALSE)
    }
    assemble()
}
