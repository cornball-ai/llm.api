# OpenAI Codex Responses provider
#
# OAuth -- device login, token refresh, on-disk caching, and account-id
# extraction -- lives in tinyoauth (tinyoauth::oauth_token_openai_codex and
# friends). This file keeps the Codex-specific provider logic (Responses body,
# SSE merge, tool handling, usage/cost) plus thin credential adapters over
# tinyoauth. The OAuth client id and endpoints are defined by
# tinyoauth::openai_codex_client().

#' OpenAI Codex subscription credentials
#'
#' Builds a zero-argument credentials function for the OpenAI Codex provider.
#' Tokens are obtained, cached, and refreshed by tinyoauth (see
#' \code{\link[tinyoauth]{oauth_token_openai_codex}}); this returns the request
#' headers (\code{Authorization} and \code{chatgpt-account-id}) for the current
#' token.
#'
#' Environment variables still override the cache when set:
#' \itemize{
#'   \item \code{OPENAI_CODEX_ACCESS_TOKEN}
#'   \item \code{OPENAI_CODEX_ACCOUNT_ID}
#' }
#'
#' @param access_token Optional access token. If omitted, read from
#'   \code{OPENAI_CODEX_ACCESS_TOKEN}, then from the tinyoauth cache.
#' @param account_id Optional ChatGPT account id. If omitted, read from
#'   \code{OPENAI_CODEX_ACCOUNT_ID}, then from the access-token JWT.
#' @return A zero-argument credentials function returning request headers.
#' @export
openai_codex_credentials <- function(access_token = Sys.getenv("OPENAI_CODEX_ACCESS_TOKEN", ""),
                                     account_id = Sys.getenv("OPENAI_CODEX_ACCOUNT_ID", "")) {
    if (identical(access_token, "")) {
        access_token <- NULL
    }
    if (identical(account_id, "")) {
        account_id <- NULL
    }

    function() {
        at <- access_token
        acct <- account_id
        if (is.null(at)) {
            tok <- tinyoauth::oauth_token_openai_codex(login = FALSE)
            if (is.null(tok)) {
                stop("No OpenAI Codex credentials available. Run ",
                     "openai_codex_login() (or set OPENAI_CODEX_ACCESS_TOKEN).",
                     call. = FALSE)
            }
            at <- tok$access_token
            acct <- acct %||% tok$account_id
        }
        acct <- acct %||% tinyoauth::openai_codex_account_id(at)
        if (is.null(acct)) {
            stop("Can't determine ChatGPT account id from the access token.",
                 call. = FALSE)
        }
        list(Authorization = paste("Bearer", at),
             `chatgpt-account-id` = acct)
    }
}

#' Log in to OpenAI Codex with a device-code flow
#'
#' Runs tinyoauth's ChatGPT Codex device-login flow, caching the token for reuse
#' across sessions, and returns an \code{\link{openai_codex_credentials}}
#' callback.
#'
#' @param timeout Maximum number of seconds to wait for login.
#' @param open_url Logical. Whether to open the verification URL in a browser.
#' @return A zero-argument credentials function, invisibly. You don't normally
#'   need it: the cached token is picked up automatically by
#'   \code{chat(provider = "openai_codex")} and friends.
#' @export
openai_codex_login <- function(timeout = 600, open_url = interactive()) {
    tok <- tinyoauth::oauth_token_openai_codex(open_url = open_url,
                                               timeout = timeout)
    acct <- if (!is.null(tok$account_id)) {
        paste0(" (account ", tok$account_id, ")")
    } else {
        ""
    }
    message("Logged in to OpenAI Codex", acct,
            ". Token cached; no need to log in again.")
    invisible(openai_codex_credentials())
}

#' Chat with OpenAI Codex
#'
#' Convenience wrapper for ChatGPT subscription-backed Codex models.
#'
#' @inheritParams chat
#' @return The assistant's response as a list. See \code{\link{chat}}.
#' @export
#' @examples
#' \dontrun{
#' creds <- openai_codex_login()
#' chat_openai_codex("Write a small R function", credentials = creds)
#' }
chat_openai_codex <- function(prompt, model = "gpt-5.5", ...) {
    chat(prompt, model = model, provider = "openai_codex", ...)
}

.openai_codex_body <- function(messages, tools, system, model, ...) {
    extra <- list(...)
    if (is.null(system)) {
        extracted <- .openai_codex_extract_system(messages)
        system <- extracted$system %||% "You are a helpful assistant."
        messages <- extracted$messages
    }

    reasoning <- NULL
    if (!is.null(extra$reasoning_effort)) {
        reasoning <- list(effort = extra$reasoning_effort, summary = "auto")
        extra$reasoning_effort <- NULL
    }

    body <- list(
                 model = model,
                 instructions = system,
                 input = .openai_codex_messages_to_input(messages),
                 stream = TRUE,
                 text = list(verbosity = extra$text_verbosity %||% "low"),
                 reasoning = reasoning,
                 include = list("reasoning.encrypted_content"),
                 store = FALSE
    )
    extra$text_verbosity <- NULL

    if (length(tools) > 0L) {
        body$tools <- tools
        body$tool_choice <- "auto"
        body$parallel_tool_calls <- TRUE
    }
    for (name in names(extra)) {
        body[[name]] <- extra[[name]]
    }
    body$stream <- TRUE
    body
}

.openai_codex_extract_system <- function(messages) {
    if (length(messages) == 0L) {
        return(list(system = NULL, messages = messages))
    }
    first <- messages[[1L]]
    if (is.list(first) && identical(first$role, "system")) {
        return(list(system = first$content, messages = messages[-1L]))
    }
    list(system = NULL, messages = messages)
}

.openai_codex_messages_to_input <- function(messages) {
    input <- list()
    for (msg in messages) {
        if (is.list(msg) && identical(msg$type, ".openai_codex_output")) {
            input <- c(input, msg$output)
        } else if (is.list(msg) &&
            identical(msg$type, "function_call_output")) {
            input[[length(input) + 1L]] <- msg
        } else if (is.list(msg) && !is.null(msg$role)) {
            role <- msg$role
            content <- msg$content %||% ""
            if (is.character(content)) {
                content_type <- if (identical(role, "assistant")) {
                    "output_text"
                } else {
                    "input_text"
                }
                content <- list(list(type = content_type, text = content))
            }
            input[[length(input) + 1L]] <- list(role = role, content = content)
        } else {
            input[[length(input) + 1L]] <- msg
        }
    }
    input
}

.openai_codex_request <- function(messages, tools, system, model, config, ...) {
    url <- paste0(config$base_url, config$chat_path)
    credentials <- config$credentials()
    headers <- c(
                 "Content-Type" = "application/json",
                 "OpenAI-Beta" = "responses=experimental",
                 "originator" = "llm.api",
                 "accept" = "text/event-stream",
                 unlist(credentials)
    )
    body <- .openai_codex_body(messages, tools, system, model, ...)
    .openai_codex_post_sse(url, body, headers)
}

.openai_codex_post_sse <- function(url, body, headers) {
    h <- curl::new_handle()
    curl::handle_setopt(
                        h,
                        customrequest = "POST",
                        postfields = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null")
    )
    curl::handle_setheaders(h, .list = as.list(headers))

    result <- NULL
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
            if (!startsWith(line, "data: ") ||
                identical(line, "data: [DONE]")) {
                next
            }
            chunk <- tryCatch(
                              jsonlite::fromJSON(substring(line, 7L), simplifyVector = FALSE),
                              error = function(e) NULL
            )
            if (!is.null(chunk)) {
                result <<- .openai_codex_merge_chunk(result, chunk)
            }
        }
        length(data)
    }

    resp <- curl::curl_fetch_stream(url, callback, handle = h)
    if (resp$status_code >= 400) {
        err <- tryCatch(jsonlite::fromJSON(raw_text, simplifyVector = FALSE),
                        error = function(e) list(error = list(message = raw_text)))
        message <- err$error$message %||% err$detail %||% raw_text
        stop("API error (", resp$status_code, "): ", message, call. = FALSE)
    }
    result %||% list(output = list(), usage = NULL)
}

.openai_codex_merge_chunk <- function(result, chunk) {
    if (chunk$type %in% c("response.created", "response.in_progress")) {
        return(result %||% chunk$response)
    }
    if (identical(chunk$type, "response.output_item.added")) {
        result <- result %||% list(output = list())
        result$output[[chunk$output_index + 1L]] <- chunk$item
        return(result)
    }
    if (identical(chunk$type, "response.function_call_arguments.delta")) {
        result <- result %||% list(output = list())
        idx <- chunk$output_index + 1L
        result$output[[idx]]$arguments <- paste0(
            result$output[[idx]]$arguments %||% "",
            chunk$delta %||% ""
        )
        return(result)
    }
    if (identical(chunk$type, "response.function_call_arguments.done")) {
        result <- result %||% list(output = list())
        result$output[[chunk$output_index + 1L]]$arguments <- chunk$arguments
        return(result)
    }
    if (identical(chunk$type, "response.output_item.done")) {
        result <- result %||% list(output = list())
        result$output[[chunk$output_index + 1L]] <- chunk$item
        return(result)
    }
    if (chunk$type %in% c("response.done", "response.completed",
                          "response.incomplete")) {
        response <- chunk$response
        if (length(response$output %||% list()) == 0L &&
            length(result$output %||% list()) > 0L) {
            response$output <- result$output
        }
        return(response)
    }
    if (identical(chunk$type, "response.failed") ||
        identical(chunk$type, "error")) {
        error <- chunk$response$error %||% chunk$error
        message <- chunk$message %||% error$message %||% error$code %||%
        "Unknown Codex error"
        stop("OpenAI Codex request failed: ", message, call. = FALSE)
    }
    result
}

.openai_codex_parse_response <- function(resp) {
    text_parts <- character()
    tool_calls <- list()
    for (output in resp$output %||% list()) {
        if (identical(output$type, "message")) {
            for (content in output$content %||% list()) {
                if (!is.null(content$text)) {
                    text_parts <- c(text_parts, content$text)
                }
            }
        } else if (identical(output$type, "function_call")) {
            args <- tryCatch(
                             jsonlite::fromJSON(output$arguments %||% "{}",
                    simplifyVector = FALSE),
                             error = function(e) list()
            )
            tool_calls[[length(tool_calls) + 1L]] <- list(
                id = output$call_id %||% output$id,
                name = output$name,
                arguments = args
            )
        }
    }

    list(
         text = paste(text_parts, collapse = "\n"),
         tool_calls = tool_calls,
         assistant_message = list(type = ".openai_codex_output",
                                  output = resp$output %||% list()),
         usage = .openai_codex_usage(resp$usage)
    )
}

.openai_codex_usage <- function(usage) {
    if (is.null(usage)) {
        return(NULL)
    }
    if (!is.null(usage$prompt_tokens)) {
        return(usage)
    }
    list(
         prompt_tokens = usage$input_tokens %||% 0L,
         completion_tokens = usage$output_tokens %||% 0L,
         total_tokens = usage$total_tokens %||%
         ((usage$input_tokens %||% 0L) + (usage$output_tokens %||% 0L)),
         prompt_tokens_details = list(
                                      cached_tokens = usage$input_tokens_details$cached_tokens %||% 0L
        )
    )
}

.chat_openai_codex <- function(body, config, stream) {
    if (!is.null(body$credentials)) {
        config$credentials <- body$credentials
        body$credentials <- NULL
    }
    extracted <- .openai_codex_extract_system(body$messages)
    extra <- body
    extra$model <- NULL
    extra$messages <- NULL
    extra$stream <- NULL
    resp <- do.call(
                    .openai_codex_request,
                    c(list(messages = extracted$messages,
                           tools = list(),
                           system = extracted$system,
                           model = body$model,
                           config = config),
                      extra)
    )
    parsed <- .openai_codex_parse_response(resp)
    if (isTRUE(stream) && nzchar(parsed$text)) {
        cat(parsed$text, "\n", sep = "")
    }
    list(content = parsed$text, thinking = NULL, finish_reason = NULL,
         usage = parsed$usage)
}

.agent_openai_codex <- function(messages, tools, system, model, config, ...) {
    extra <- list(...)
    if (!is.null(extra$credentials)) {
        config$credentials <- extra$credentials
        extra$credentials <- NULL
    }
    resp <- do.call(
                    .openai_codex_request,
                    c(list(messages = messages, tools = tools, system = system,
                           model = model, config = config),
                      extra)
    )
    .openai_codex_parse_response(resp)
}

