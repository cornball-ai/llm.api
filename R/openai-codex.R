# OpenAI Codex Responses provider

# Public OAuth native-app client id for OpenAI's Codex-compatible
# ChatGPT subscription flow. This identifies the OAuth app/flow; it is
# not a user secret. Never commit access tokens, refresh tokens, or
# locally stored OAuth credential files.
.openai_codex_client_id <- "app_EMoamEEZ73f0CkXaXp7hrann"
.openai_codex_auth_base_url <- "https://auth.openai.com"
.openai_codex_token_url <- paste0(.openai_codex_auth_base_url, "/oauth/token")
.openai_codex_device_user_code_url <- paste0(
    .openai_codex_auth_base_url,
    "/api/accounts/deviceauth/usercode"
)
.openai_codex_device_token_url <- paste0(
    .openai_codex_auth_base_url,
    "/api/accounts/deviceauth/token"
)
.openai_codex_device_verification_uri <- paste0(
    .openai_codex_auth_base_url,
    "/codex/device"
)
.openai_codex_device_redirect_uri <- paste0(
    .openai_codex_auth_base_url,
    "/deviceauth/callback"
)
.openai_codex_jwt_claim_path <- "https://api.openai.com/auth"

#' OpenAI Codex subscription credentials
#'
#' Creates a zero-argument credentials function suitable for the
#' OpenAI Codex provider. If a refresh token is supplied, the access
#' token is refreshed automatically when needed.
#'
#' By default, credentials are read from:
#' \itemize{
#'   \item \code{OPENAI_CODEX_ACCESS_TOKEN}
#'   \item \code{OPENAI_CODEX_REFRESH_TOKEN}
#'   \item \code{OPENAI_CODEX_EXPIRES_AT} (Unix timestamp, seconds)
#'   \item \code{OPENAI_CODEX_ACCOUNT_ID}
#' }
#'
#' @param access_token OAuth access token. If omitted, read from
#'   \code{OPENAI_CODEX_ACCESS_TOKEN}.
#' @param refresh_token OAuth refresh token. If omitted, read from
#'   \code{OPENAI_CODEX_REFRESH_TOKEN}.
#' @param expires_at Expiry time as a Unix timestamp in seconds, or
#'   NULL if unknown.
#' @param account_id ChatGPT account id. Usually extracted from the
#'   access token.
#' @return A zero-argument credentials function returning request headers.
#' @export
openai_codex_credentials <- function(access_token = Sys.getenv("OPENAI_CODEX_ACCESS_TOKEN",
        ""),
                                     refresh_token = Sys.getenv("OPENAI_CODEX_REFRESH_TOKEN", ""),
                                     expires_at = .openai_codex_env_number("OPENAI_CODEX_EXPIRES_AT"),
                                     account_id = Sys.getenv("OPENAI_CODEX_ACCOUNT_ID", "")) {
    if (identical(access_token, "")) {
        access_token <- NULL
    }
    if (identical(refresh_token, "")) {
        refresh_token <- NULL
    }
    if (identical(account_id, "")) {
        account_id <- NULL
    }

    state <- new.env(parent = emptyenv())
    state$access_token <- access_token
    state$refresh_token <- refresh_token
    state$expires_at <- .openai_codex_normalize_expires(expires_at)
    state$account_id <- account_id

    credentials <- function() {
        .openai_codex_refresh_if_needed(state)

        if (is.null(state$access_token)) {
            stop("No OpenAI Codex credentials are available. Run ",
                 "openai_codex_login() or set OPENAI_CODEX_REFRESH_TOKEN.",
                 call. = FALSE)
        }

        account_id <- state$account_id %||%
        .openai_codex_account_id(state$access_token)
        if (is.null(account_id)) {
            stop("Can't determine ChatGPT account id from ",
                 "OPENAI_CODEX_ACCESS_TOKEN.", call. = FALSE)
        }
        state$account_id <- account_id

        list(
             Authorization = paste("Bearer", state$access_token),
             `chatgpt-account-id` = account_id
        )
    }

    attr(credentials, "token") <- function() {
        list(
             access = state$access_token,
             refresh = state$refresh_token,
             expires = state$expires_at,
             account_id = state$account_id
        )
    }
    credentials
}

#' Log in to OpenAI Codex with a device-code flow
#'
#' Starts a ChatGPT Codex OAuth device-code login and returns an
#' \code{openai_codex_credentials()} callback for the current R session.
#'
#' @param timeout Maximum number of seconds to wait for login.
#' @param open_url Logical. Whether to open the verification URL in a
#'   browser.
#' @return A zero-argument credentials function.
#' @export
openai_codex_login <- function(timeout = 600, open_url = interactive()) {
    device <- .openai_codex_start_device_auth()
    message("Open ", .openai_codex_device_verification_uri,
            " and enter code: ", device$user_code)
    if (isTRUE(open_url)) {
        utils::browseURL(.openai_codex_device_verification_uri)
    }

    code <- .openai_codex_poll_device_auth(device, device$interval, timeout)
    token <- .openai_codex_exchange_code(
        code$authorization_code,
        code$code_verifier
    )

    openai_codex_credentials(
                             access_token = token$access,
                             refresh_token = token$refresh,
                             expires_at = token$expires,
                             account_id = token$account_id
    )
}

#' Refresh an OpenAI Codex OAuth token
#'
#' @param refresh_token OAuth refresh token. Defaults to
#'   \code{OPENAI_CODEX_REFRESH_TOKEN}.
#' @return A list with \code{access}, \code{refresh}, \code{expires},
#'   and \code{account_id}.
#' @export
openai_codex_refresh <- function(
                                 refresh_token = Sys.getenv("OPENAI_CODEX_REFRESH_TOKEN", "")
) {
    if (!nzchar(refresh_token)) {
        stop("OPENAI_CODEX_REFRESH_TOKEN is not set.", call. = FALSE)
    }
    .openai_codex_refresh_token(refresh_token)
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

.openai_codex_env_number <- function(name) {
    value <- Sys.getenv(name, "")
    if (identical(value, "")) {
        NULL
    } else {
        as.numeric(value)
    }
}

.openai_codex_normalize_expires <- function(expires) {
    if (is.null(expires) || is.na(expires)) {
        return(NULL)
    }
    expires <- as.numeric(expires)
    if (expires > 1e12) {
        expires <- expires / 1000
    }
    expires
}

.openai_codex_refresh_if_needed <- function(state) {
    needs_refresh <- is.null(state$access_token) ||
    (!is.null(state$expires_at) &&
        state$expires_at <= as.numeric(Sys.time()) + 30)

    if (!needs_refresh || is.null(state$refresh_token)) {
        return(invisible())
    }

    token <- .openai_codex_refresh_token(state$refresh_token)
    state$access_token <- token$access
    state$refresh_token <- token$refresh
    state$expires_at <- token$expires
    state$account_id <- token$account_id
    invisible()
}

.openai_codex_account_id <- function(token) {
    payload <- .openai_codex_jwt_payload(token)
    auth <- payload[[.openai_codex_jwt_claim_path]]
    account_id <- auth$chatgpt_account_id
    if (is.character(account_id) && length(account_id) == 1L &&
        nzchar(account_id)) {
        account_id
    } else {
        NULL
    }
}

.openai_codex_jwt_payload <- function(token) {
    parts <- strsplit(token, ".", fixed = TRUE)[[1]]
    if (length(parts) != 3L) {
        stop("Invalid OpenAI Codex access token.", call. = FALSE)
    }

    payload <- gsub("\\s+", "", parts[[2L]])
    payload <- chartr("-_", "+/", payload)
    padding <- (4L - nchar(payload) %% 4L) %% 4L
    if (padding > 0L) {
        payload <- paste0(payload, strrep("=", padding))
    }

    json <- rawToChar(jsonlite::base64_dec(payload))
    jsonlite::fromJSON(json, simplifyVector = FALSE)
}

.openai_codex_start_device_auth <- function() {
    json <- .openai_codex_post_json(
                                    .openai_codex_device_user_code_url,
                                    list(client_id = .openai_codex_client_id),
                                    headers = c("Content-Type" = "application/json")
    )
    interval <- as.numeric(json$interval %||% 5)

    if (!is.character(json$device_auth_id) ||
        !is.character(json$user_code) ||
        is.na(interval)) {
        stop("Invalid OpenAI Codex device code response.", call. = FALSE)
    }

    list(
         device_auth_id = json$device_auth_id,
         user_code = json$user_code,
         interval = interval
    )
}

.openai_codex_poll_device_auth <- function(device, interval, timeout) {
    deadline <- Sys.time() + timeout

    repeat {
        if (Sys.time() > deadline) {
            stop("OpenAI Codex device login timed out.", call. = FALSE)
        }
        Sys.sleep(interval)

        resp <- tryCatch(
                         .openai_codex_post_json(
                .openai_codex_device_token_url,
                list(device_auth_id = device$device_auth_id,
                     user_code = device$user_code),
                headers = c("Content-Type" = "application/json")
            ),
                         error = function(e) e
        )
        if (!inherits(resp, "error")) {
            if (is.character(resp$authorization_code) &&
                is.character(resp$code_verifier)) {
                return(list(
                            authorization_code = resp$authorization_code,
                            code_verifier = resp$code_verifier
                    ))
            }
            stop("Invalid OpenAI Codex device token response.", call. = FALSE)
        }

        msg <- conditionMessage(resp)
        if (grepl("deviceauth_authorization_pending|API error \\(403\\)|API error \\(404\\)",
                  msg)) {
            next
        }
        if (grepl("slow_down", msg)) {
            interval <- interval + 5
            next
        }
        stop(resp)
    }
}

.openai_codex_exchange_code <- function(code, verifier,
                                        redirect_uri = .openai_codex_device_redirect_uri) {
    .openai_codex_token_from_response(.openai_codex_post_form(
            .openai_codex_token_url,
            list(grant_type = "authorization_code",
                 client_id = .openai_codex_client_id,
                 code = code,
                 code_verifier = verifier,
                 redirect_uri = redirect_uri)
        ))
}

.openai_codex_refresh_token <- function(refresh_token) {
    .openai_codex_token_from_response(.openai_codex_post_form(
            .openai_codex_token_url,
            list(grant_type = "refresh_token",
                 refresh_token = refresh_token,
                 client_id = .openai_codex_client_id)
        ))
}

.openai_codex_token_from_response <- function(json) {
    if (!is.character(json$access_token) ||
        !is.character(json$refresh_token) ||
        is.null(json$expires_in)) {
        stop("OpenAI Codex token response is missing required fields.",
             call. = FALSE)
    }

    access <- json$access_token
    account_id <- .openai_codex_account_id(access)
    if (is.null(account_id)) {
        stop("Failed to extract ChatGPT account id from OpenAI Codex token.",
             call. = FALSE)
    }

    list(
         access = access,
         refresh = json$refresh_token,
         expires = as.numeric(Sys.time()) + as.numeric(json$expires_in),
         account_id = account_id
    )
}

.openai_codex_post_form <- function(url, fields) {
    h <- curl::new_handle()
    curl::handle_setopt(h, customrequest = "POST")
    curl::handle_setheaders(h, .list = list("Content-Type" =
            "application/x-www-form-urlencoded"))
    curl::handle_setform(h, .list = fields)
    resp <- curl::curl_fetch_memory(url, handle = h)
    .openai_codex_decode_response(resp)
}

.openai_codex_post_json <- function(url, body, headers = character()) {
    h <- curl::new_handle()
    curl::handle_setopt(
                        h,
                        customrequest = "POST",
                        postfields = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null")
    )
    curl::handle_setheaders(h, .list = as.list(headers))
    resp <- curl::curl_fetch_memory(url, handle = h)
    .openai_codex_decode_response(resp)
}

.openai_codex_decode_response <- function(resp) {
    text <- rawToChar(resp$content)
    if (resp$status_code >= 400) {
        err <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE),
                        error = function(e) list(error = list(message = text)))
        message <- err$error$message %||% err$error$code %||% text
        stop("API error (", resp$status_code, "): ", message, call. = FALSE)
    }
    jsonlite::fromJSON(text, simplifyVector = FALSE)
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

