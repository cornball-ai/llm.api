# Invocation-scoped observers. No callback runs inside a transport retry's
# error handler: its own errors/warnings are isolated from provider behavior.
.request_runtime <- new.env(parent = emptyenv())
.request_runtime$counter <- 0
.request_runtime$started <- format(Sys.time(), "%Y%m%dT%H%M%OS6", tz = "UTC")

.request_enter <- function(callback, provider) {
    if (!is.null(callback) && !is.function(callback)) {
        stop("request_callback must be a function or NULL", call. = FALSE)
    }
    previous <- .request_runtime$current
    .request_runtime$current <- list(callback = callback, provider = provider)
    previous
}

.request_new <- function(payload, wire, model = NULL) {
    observer <- .request_runtime$current
    if (!is.function(observer$callback)) {
        return(NULL)
    }
    .request_runtime$counter <- .request_runtime$counter + 1
    request <- new.env(parent = emptyenv())
    request$id <- paste(.request_runtime$started, Sys.getpid(),
                        format(.request_runtime$counter, scientific = FALSE, trim = TRUE), sep = ":")
    request$attempt <- 0L
    request$observer <- observer
    request$payload <- as.character(payload)
    request$wire <- wire
    request$model <- model
    request
}

.request_notify <- function(request, phase, ...) {
    if (is.null(request)) {
        return(invisible(NULL))
    }
    event <- c(list(version = 1L, phase = phase, request_id = request$id,
                    attempt = request$attempt,
                    attempt_id = paste0(request$id, ":", request$attempt),
                    provider = request$observer$provider, wire = request$wire,
                    requested_model = request$model,
                    ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC")), list(...))
    tryCatch(suppressWarnings(request$observer$callback(event)), error = function(e) {
        if (!isTRUE(.request_runtime$notice)) {
            .request_runtime$notice <- TRUE
            tryCatch(message("llm.api request_callback failed; the request continues."),
                     error = function(e) NULL)
        }
        NULL
    })
    invisible(NULL)
}

.request_headers <- function(headers) {
    if (is.raw(headers)) {
        headers <- rawToChar(headers)
    }
    if (!is.character(headers)) {
        return(list())
    }
    lines <- unlist(strsplit(headers, "\r?\n"))
    keys <- tolower(trimws(sub(":.*$", "", lines)))
    keep <- keys %in% c("request-id", "x-request-id", "openai-request-id")
    values <- trimws(sub("^[^:]*:", "", lines[keep]))
    as.list(stats::setNames(values, keys[keep]))
}

.request_metadata <- function(snapshot) {
    data <- snapshot$data
    choices <- data$choices
    finish <- if (is.data.frame(choices)) choices$finish_reason[[1L]] else
    if (length(choices)) {
        choices[[1L]]$finish_reason
    }
    list(raw_usage = data$usage, reported_model = data$model,
         response_id = data$id,
         stop_reason = data$stop_reason %||% finish %||%
         data$incomplete_details$reason %||% data$status,
         request_headers = .request_headers(snapshot$response$headers),
         http_status = snapshot$response$status_code,
         cancelled = isTRUE(snapshot$cancelled))
}

# Return the transport value unchanged. The JSON parse here is observational;
# adapters retain their existing parsing/error behavior. Streaming supplies its
# current assembled state, including usage already received before an error.
.request_fetch <- function(request, expr, snapshot = NULL) {
    if (is.null(request)) {
        return(force(expr))
    }
    request$attempt <- request$attempt + 1L
    .request_notify(request, "start", serialized_request = request$payload)
    started <- proc.time()[["elapsed"]]
    inspect <- function(value = NULL) {
        if (is.function(snapshot)) {
            return(snapshot(value))
        }
        data <- if (!is.null(value$content))
        jsonlite::fromJSON(rawToChar(value$content), simplifyVector = FALSE)
        list(response = value, data = data)
    }
    ended <- FALSE
    finish <- function(value = NULL, condition = NULL) {
        if (ended) {
            return(invisible(NULL))
        }
        ended <<- TRUE
        snap <- tryCatch(inspect(value),
                         error = function(e) list(parse_error = e))
        condition <- condition %||% snap$parse_error
        metadata <- tryCatch(.request_metadata(snap), error = function(e) list())
        failed <- !is.null(condition) ||
        isTRUE(snap$response$status_code >= 400)
        phase <- if (failed) "error" else "end"
        status <- if (inherits(condition, "interrupt")) "interrupted" else if (failed) "error" else
        if (isTRUE(snap$cancelled)) {
            "cancelled"
        } else {
            "complete"
        }
        do.call(.request_notify, c(list(request = request, phase = phase,
                                        status = status, elapsed_ms = (proc.time()[["elapsed"]] - started) * 1000,
                                        condition_classes = if (!is.null(condition)) as.list(class(condition)),
                                        condition_message = if (!is.null(condition)) conditionMessage(condition)), metadata))
    }
    value <- withCallingHandlers(force(expr), error = function(e) finish(condition = e),
                                 interrupt = function(e) finish(condition = e))
    finish(value)
    value
}
