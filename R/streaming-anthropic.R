# Streaming over the Anthropic Messages wire.
#
# A third event vocabulary, and the fiddliest of the three. Content
# arrives as indexed blocks that open, receive deltas, and close, and a
# tool call's arguments stream as `partial_json` fragments that have to
# be spliced and only then parsed -- so a dropped fragment yields a JSON
# parse failure or, worse, a shorter object that still parses.
#
# The return is assembled into exactly the non-streamed shape -- a
# `content` list of blocks plus `usage` -- so .agent_anthropic() parses
# one shape and the two paths can be compared with identical().

# Merge one streaming event into the block accumulator.
#
# Keyed on the wire's `index`, like the chat-completions path and for
# the same reason: blocks interleave, and appending in arrival order
# would braid a tool call's arguments into a text block.
#
# Returns the new state and, separately, any text the caller should
# hand to on_delta -- rather than calling on_delta itself. That
# callback can raise a cancel, and a cancel raised in here unwinds
# before the caller assigns the returned state, losing the whole event
# that was being merged. The delta that triggered the stop was then
# missing from the text the cancelled response reported.
.llm_anthropic_merge_event <- function(state, ev) {
    emit <- NULL
    done <- function(state) list(state = state, emit = emit)
    type <- ev$type
    if (identical(type, "message_start")) {
        state$usage <- ev$message$usage
        return(done(state))
    }
    if (identical(type, "content_block_start")) {
        key <- as.character(ev$index %||% 0L)
        block <- ev$content_block
        # A tool_use block's `input` arrives as JSON text in the deltas,
        # not as the object the start event carries (which is empty).
        # Held as a string until the block closes.
        if (identical(block$type, "tool_use")) {
            block$partial_json <- ""
        }
        state$blocks[[key]] <- block
        return(done(state))
    }
    if (identical(type, "content_block_delta")) {
        key <- as.character(ev$index %||% 0L)
        block <- state$blocks[[key]]
        if (is.null(block)) {
            return(done(state))
        }
        delta <- ev$delta
        if (identical(delta$type, "text_delta")) {
            block$text <- paste0(block$text %||% "", delta$text %||% "")
            emit <- delta$text
        } else if (identical(delta$type, "input_json_delta")) {
            block$partial_json <- paste0(block$partial_json %||% "",
                delta$partial_json %||% "")
        } else if (identical(delta$type, "thinking_delta")) {
            block$thinking <- paste0(block$thinking %||% "",
                                     delta$thinking %||% "")
        } else if (identical(delta$type, "signature_delta")) {
            block$signature <- paste0(block$signature %||% "",
                                      delta$signature %||% "")
        }
        state$blocks[[key]] <- block
        return(done(state))
    }
    if (identical(type, "content_block_stop")) {
        key <- as.character(ev$index %||% 0L)
        block <- state$blocks[[key]]
        if (!is.null(block) && identical(block$type, "tool_use")) {
            # Parsed only now that every fragment is in. An empty
            # argument object streams as "{}" or as nothing at all, and
            # both have to end up as the empty named list the
            # non-streamed wire delivers.
            json <- block$partial_json %||% ""
            block$partial_json <- NULL
            block$input <- if (nzchar(json)) {
                tryCatch(jsonlite::fromJSON(json, simplifyVector = FALSE),
                         error = function(e) list())
            } else {
                block$input %||% list()
            }
            state$blocks[[key]] <- block
        }
        return(done(state))
    }
    if (identical(type, "message_delta")) {
        if (!is.null(ev$delta$stop_reason)) {
            state$stop_reason <- ev$delta$stop_reason
        }
        # Output tokens arrive here; input tokens arrived at
        # message_start. Merged rather than replaced, or the request's
        # own cost disappears.
        for (nm in names(ev$usage %||% list())) {
            state$usage[[nm]] <- ev$usage[[nm]]
        }
        return(done(state))
    }
    if (identical(type, "error")) {
        msg <- ev$error$message %||% ev$error$type %||% "Unknown error"
        stop("API error: ", msg, call. = FALSE)
    }
    done(state)
}

.llm_anthropic_assemble <- function(state) {
    blocks <- state$blocks
    ordered <- if (length(blocks)) {
        unname(blocks[order(as.integer(names(blocks)))])
    } else {
        list()
    }
    list(content = ordered, usage = state$usage,
         stop_reason = state$stop_reason, role = "assistant",
         type = "message")
}

.anthropic_post_sse <- function(url, body, headers, on_delta = NULL) {
    .llm_assert_translated(body$messages, "the request body")
    body$stream <- TRUE
    payload <- jsonlite::toJSON(body, auto_unbox = TRUE, null = "null")

    state <- list(blocks = list(), usage = NULL, stop_reason = NULL)
    buffer <- ""
    raw_text <- ""

    callback <- function(data) {
        text <- rawToChar(data)
        raw_text <<- paste0(raw_text, text)
        buffer <<- paste0(buffer, text)
        lines <- strsplit(buffer, "\n", fixed = TRUE)[[1L]]
        if (!endsWith(buffer, "\n")) {
            buffer <<- lines[[length(lines)]]
            lines <- lines[-length(lines)]
        } else {
            buffer <<- ""
        }
        for (line in lines) {
            line <- trimws(line)
            # Anthropic sends an `event:` line before each `data:` line.
            # The data payload carries its own `type`, so the event line
            # is redundant and skipped rather than parsed.
            if (!startsWith(line, "data: ")) {
                next
            }
            ev <- tryCatch(
                           jsonlite::fromJSON(substring(line, 7L), simplifyVector = FALSE),
                           error = function(e) NULL)
            if (is.null(ev)) {
                next
            }
            merged <- .llm_anthropic_merge_event(state, ev)
            # State first, emit second. on_delta can raise a cancel,
            # and a cancel raised before this assignment discards the
            # event that caused it.
            state <<- merged$state
            .llm_emit_delta(on_delta, merged$emit)
        }
        length(data)
    }

    # Fresh handle and fresh parser state per attempt, so a retry (see
    # .llm_transport_retry) starts from nothing rather than from the
    # tail of a connection that died.
    run <- function() {
        state <<- list(blocks = list(), usage = NULL, stop_reason = NULL)
        buffer <<- ""
        raw_text <<- ""
        h <- curl::new_handle()
        curl::handle_setopt(h, customrequest = "POST", postfields = payload)
        curl::handle_setheaders(h, .list = as.list(headers))
        .llm_with_cancel(curl::curl_fetch_stream(url, callback, handle = h))
    }
    fetched <- .llm_transport_retry(run, received = function() nzchar(raw_text))
    if (fetched$cancelled) {
        partial <- .llm_anthropic_assemble(state)
        attr(partial, "llm_cancelled") <- TRUE
        return(partial)
    }
    resp <- fetched$value
    if (resp$status_code >= 400) {
        err <- tryCatch(jsonlite::fromJSON(raw_text, simplifyVector = FALSE),
                        error = function(e) NULL)
        stop("API error (", resp$status_code, "): ",
             err$error$message %||% raw_text %||% "Unknown error",
             call. = FALSE)
    }
    .llm_anthropic_assemble(state)
}
