# Streaming: getting the model's text out while it is still being
# written, and stopping it early.
#
# These are one mechanism, not two. A caller can only interrupt a
# response it is watching, so the callback that delivers a sentence
# early is also the only place with standing to say stop. Anything
# that reads the whole response first has already paid for all of it.

#' Stop a streaming response early
#'
#' Called from inside an \code{on_delta} callback to abandon the
#' request. The connection is closed, the provider stops generating,
#' and \code{\link{agent}} returns what had arrived so far with
#' \code{cancelled = TRUE}.
#'
#' This is what makes barge-in possible: a caller speaking the model's
#' text aloud can stop mid-sentence when the user starts talking, and
#' stop paying for the rest of a reply nobody is listening to.
#'
#' Raising it outside a stream is an ordinary error, which is the
#' honest outcome -- there is nothing to cancel.
#'
#' @param message Character. Reason, for the condition object.
#' @return Never returns; raises a condition of class
#'   \code{llm_cancelled}.
#' @seealso \code{\link{agent}}
#' @examples
#' \dontrun{
#' spoken <- 0
#' agent("tell me a long story", provider = "openai_codex",
#'       on_delta = function(text) {
#'           spoken <<- spoken + nchar(text)
#'           if (spoken > 200) llm_cancel("heard enough")
#'       })
#' }
#' @export
llm_cancel <- function(message = "cancelled by on_delta") {
    stop(structure(class = c("llm_cancelled", "error", "condition"),
                   list(message = message, call = NULL)))
}

# Run a streaming fetch, answering whether it was cancelled rather than
# letting the condition escape.
#
# Inherits from "error" so an uncaught llm_cancel() outside a stream is
# an ordinary error rather than silently unwinding to nowhere. Caught by
# its own class here, so it never reaches a caller's error handler as a
# failure -- a cancelled request succeeded at what it was asked to do.
.llm_with_cancel <- function(expr) {
    cancelled <- FALSE
    value <- withCallingHandlers(
                                 tryCatch(expr, llm_cancelled = function(c) {
        cancelled <<- TRUE
        NULL
    }),
                                 warning = function(w) w)
    list(value = value, cancelled = cancelled)
}

# Hand one text delta to the caller's callback.
#
# Guarded rather than called directly: a provider that emits an empty
# or non-character delta should not reach the callback at all, because
# a callback counting characters to decide when to speak would see a
# fragment that is not text and act on it.
.llm_emit_delta <- function(on_delta, text) {
    if (is.null(on_delta)) {
        return(invisible(NULL))
    }
    if (!is.character(text) || length(text) != 1L || is.na(text) ||
        !nzchar(text)) {
        return(invisible(NULL))
    }
    on_delta(text)
    invisible(NULL)
}
