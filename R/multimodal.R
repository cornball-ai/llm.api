# Multimodal input: images in a user turn.
#
# Every provider here accepts images inside the chat request itself --
# there is no separate vision endpoint anywhere -- and every one of them
# spells the block differently. Three dialects across seven providers:
#
#   Anthropic Messages   {type: "image",
#                         source: {type: "base64", media_type, data}}
#   Chat Completions     {type: "image_url",
#                         image_url: {url: "data:<mime>;base64,<data>"}}
#   OpenAI Responses     {type: "input_image",
#                         image_url: "data:<mime>;base64,<data>"}
#
# A caller builds llm_content("what is this?", llm_image("shot.png"))
# and the translation happens where the request is serialized, because
# the dialect is a property of the wire format rather than of the
# caller. Nothing changes for a plain character prompt: the neutral
# form is only produced when a caller asks for it.

#' Image input for a chat message
#'
#' Wraps an image so it can be sent to a vision-capable model as part of
#' a user turn. Combine with text using \code{\link{llm_content}} and
#' pass the result as \code{prompt} to \code{\link{chat}} or
#' \code{\link{agent}}.
#'
#' Provider-neutral: the block is translated into the dialect of
#' whichever provider the request goes to, so the same call works
#' against Anthropic, the Chat Completions API, and the OpenAI
#' Responses API.
#'
#' The image travels inline, base64-encoded, which is what every one of
#' these providers accepts without a prior upload. Providers cap how
#' large that may be (single-digit to low-double-digit megabytes,
#' depending); resize before calling if the file is big.
#'
#' @param path Path to an image file. Exactly one of \code{path} and
#'   \code{data} is required.
#' @param data Raw vector of image bytes, or a character scalar that is
#'   already base64.
#' @param mime MIME type such as "image/png". Inferred from
#'   \code{path}'s extension when it is given; required with
#'   \code{data}, which carries no name to infer from.
#' @return An \code{llm_image} object.
#' @seealso \code{\link{llm_content}}
#' @examples
#' \dontrun{
#' chat(llm_content("What is in this picture?", llm_image("shot.png")),
#'      provider = "anthropic")
#' }
#' @export
llm_image <- function(path = NULL, data = NULL, mime = NULL) {
    if (is.null(path) == is.null(data)) {
        stop("llm_image(): supply exactly one of `path` and `data`.",
             call. = FALSE)
    }
    if (!is.null(path)) {
        if (!is.character(path) || length(path) != 1L || is.na(path)) {
            stop("llm_image(): `path` must be a single file path.",
                 call. = FALSE)
        }
        if (!file.exists(path)) {
            stop("llm_image(): no such file: ", path, call. = FALSE)
        }
        mime <- mime %||% .llm_image_mime(path)
        data <- readBin(path, "raw", file.size(path))
    }
    if (is.null(mime) || !is.character(mime) || length(mime) != 1L ||
        is.na(mime) || !nzchar(mime)) {
        stop("llm_image(): `mime` is required (e.g. \"image/png\"), and ",
             "cannot be inferred from raw bytes.", call. = FALSE)
    }
    encoded <- if (is.raw(data)) {
        .llm_base64(data)
    } else if (is.character(data) && length(data) == 1L && !is.na(data)) {
        # Already base64. Stripped anyway, on the same reasoning as
        # below: a caller that encoded it with a wrapping encoder hands
        # over a string the API rejects, and the error names the field
        # rather than the newlines.
        gsub("[\r\n]", "", data)
    } else {
        stop("llm_image(): `data` must be a raw vector or a base64 string.",
             call. = FALSE)
    }
    structure(list(mime = mime, data = encoded), class = "llm_image")
}

#' @export
print.llm_image <- function(x, ...) {
    cat(sprintf("<llm_image %s, %s base64 chars>\n", x$mime,
                format(nchar(x$data), big.mark = ",")))
    invisible(x)
}

#' Mixed text and images for one message
#'
#' Assembles the parts of a single user turn. Character arguments are
#' text, \code{\link{llm_image}} objects are images, and the order is
#' the order the model sees them -- which matters: a question asked
#' before the picture reads differently from one asked after it.
#'
#' Pass the result as \code{prompt} to \code{\link{chat}} or
#' \code{\link{agent}}. A plain character prompt is unaffected and
#' still takes the ordinary path.
#'
#' @param ... Character scalars and \code{\link{llm_image}} objects.
#' @return An \code{llm_content} object: a list of parts.
#' @seealso \code{\link{llm_image}}
#' @examples
#' \dontrun{
#' llm_content("Describe this", llm_image("plot.png"))
#' }
#' @export
llm_content <- function(...) {
    parts <- list(...)
    if (!length(parts)) {
        stop("llm_content(): supply at least one part.", call. = FALSE)
    }
    out <- lapply(parts, function(p) {
        if (inherits(p, "llm_image")) {
            return(p)
        }
        if (is.character(p) && length(p) == 1L && !is.na(p)) {
            return(structure(list(text = p), class = "llm_text"))
        }
        stop("llm_content(): each part must be a character scalar or an ",
             "llm_image(); got ", paste(class(p), collapse = "/"), ".",
             call. = FALSE)
    })
    structure(out, class = "llm_content")
}

#' @export
print.llm_content <- function(x, ...) {
    cat(sprintf("<llm_content: %d part%s>\n", length(x),
            if (length(x) == 1L) "" else "s"))
    for (p in x) {
        if (inherits(p, "llm_image")) {
            print(p)
        } else {
            cat("  ", p$text, "\n", sep = "")
        }
    }
    invisible(x)
}

# jsonlite::base64_enc() wraps at 72 columns. A data URL with newlines
# in it is not a data URL, and what comes back is a 400 naming the
# field rather than the line breaks -- which is a slow thing to work
# out from the outside. Stripped here, once, so no caller has to know.
.llm_base64 <- function(bytes) {
    gsub("[\r\n]", "", jsonlite::base64_enc(bytes))
}

.llm_image_mime <- function(path) {
    ext <- tolower(sub(".*\\.", "", basename(path)))
    switch(ext,
           png = "image/png",
           jpg =,
           jpeg = "image/jpeg",
           gif = "image/gif",
           webp = "image/webp",
           # Named rather than guessed. Every one of these providers
           # rejects a media_type it does not support, and inventing
           # one from an unknown extension turns a clear local error
           # into a remote one.
           stop("llm_image(): cannot infer a MIME type from '", basename(path),
                "'. Pass `mime`.", call. = FALSE))
}

# The wire dialect a provider speaks. Separate from the provider name
# because seven providers share three of these, and because "openai"
# speaks two: the Responses API when web_search is on, Chat Completions
# otherwise. The serializers each name their own, which is why this is
# not derived from the provider here.
.LLM_DIALECTS <- c("anthropic", "openai", "responses")

# Translate any llm_content in a message list into one provider's
# blocks. Everything else passes through untouched, so a message list
# with no multimodal turn in it comes back identical -- which is what
# makes this safe to call unconditionally at each serialization point.
.llm_blocks <- function(messages, dialect) {
    if (!length(messages)) {
        return(messages)
    }
    dialect <- match.arg(dialect, .LLM_DIALECTS)
    lapply(messages, function(msg) {
        if (!is.list(msg) || !inherits(msg$content, "llm_content")) {
            return(msg)
        }
        msg$content <- .llm_content_blocks(msg$content, dialect,
            role = msg$role %||% "user")
        msg
    })
}

# The one thing that fails quietly here. jsonlite serializes an
# llm_content perfectly happily -- it is a list -- into an array of
# {"text": "..."} objects that no provider understands and none of them
# error on, because a message whose content is an unrecognized array is
# a message with no text in it. The model answers about nothing and
# says so politely.
#
# So the shared POST helpers check before writing, and a provider path
# added later that forgets to translate is an error at the boundary
# rather than a strange answer.
.llm_assert_translated <- function(messages, where) {
    if (!length(messages)) {
        return(invisible(TRUE))
    }
    for (m in messages) {
        if (is.list(m) && inherits(m$content, "llm_content")) {
            stop("llm.api: multimodal content reached ", where,
                 " untranslated. This provider path needs a ",
                 ".llm_blocks() call before it serializes.", call. = FALSE)
        }
    }
    invisible(TRUE)
}

.llm_content_blocks <- function(content, dialect, role = "user") {
    lapply(content, function(p) {
        if (inherits(p, "llm_image")) {
            .llm_image_block(p, dialect)
        } else {
            .llm_text_block(p$text, dialect, role)
        }
    })
}

.llm_text_block <- function(text, dialect, role) {
    if (identical(dialect, "responses")) {
        # The Responses API distinguishes what was said to the model
        # from what it said back, and rejects the wrong one for a role.
        if (identical(role, "assistant")) {
            type <- "output_text"
        } else {
            type <- "input_text"
        }

        return(list(type = type, text = text))
    }
    list(type = "text", text = text)
}

.llm_image_block <- function(img, dialect) {
    switch(dialect,
           anthropic = list(type = "image",
                            source = list(type = "base64", media_type = img$mime,
                data = img$data)),
           openai = list(type = "image_url",
                         image_url = list(url = .llm_data_url(img))),
           responses = list(type = "input_image", image_url = .llm_data_url(img)))
}

.llm_data_url <- function(img) {
    paste0("data:", img$mime, ";base64,", img$data)
}

# Whether a message list carries any image at all. Providers that
# cannot accept one should refuse rather than send it and be told no by
# the API, and a caller wanting to gate on the model can ask the same
# question.
#
# Exported because the gate belongs to whoever chose the model:
# llm.api knows the dialects, not which build of a given model behind
# an OpenAI-compatible gateway has vision turned on.
#' Does this content carry an image?
#'
#' TRUE when the argument is an \code{\link{llm_content}} holding at
#' least one \code{\link{llm_image}}, or is an \code{llm_image} itself.
#' Useful for gating: a caller that may or may not be pointed at a
#' vision-capable model can ask before sending.
#'
#' @param x An \code{llm_content}, an \code{llm_image}, or anything
#'   else (FALSE).
#' @return A single logical.
#' @examples
#' llm_has_image("just text")
#' @export
llm_has_image <- function(x) {
    if (inherits(x, "llm_image")) {
        return(TRUE)
    }
    if (!inherits(x, "llm_content")) {
        return(FALSE)
    }
    any(vapply(x, inherits, logical(1), "llm_image"))
}
