# Provider-neutral image input, and the three wire dialects it becomes.
#
# The assertions that matter here are by value, not by class: a block
# whose field is named wrong is a block every one of these APIs accepts
# and ignores, so the model answers about nothing and nothing errors.

png_bytes <- as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
tmp_png <- tempfile(fileext = ".png")
writeBin(png_bytes, tmp_png)

# ---- llm_image ----

img <- llm.api::llm_image(tmp_png)
expect_inherits(img, "llm_image")
expect_identical(img$mime, "image/png")
expect_identical(img$data, jsonlite::base64_enc(png_bytes))

# The MIME comes off the extension, case-insensitively, and jpg and
# jpeg are the same type.
local({
    f <- tempfile(fileext = ".JPEG")
    writeBin(png_bytes, f)
    expect_identical(llm.api::llm_image(f)$mime, "image/jpeg")
})

# An extension nothing here knows is a local error naming the file,
# rather than a media_type the API rejects a round trip later.
local({
    f <- tempfile(fileext = ".tiff")
    writeBin(png_bytes, f)
    expect_error(llm.api::llm_image(f), "cannot infer a MIME type")
    # ... and passing one explicitly is how you override that.
    expect_identical(llm.api::llm_image(f, mime = "image/tiff")$mime,
                     "image/tiff")
})

# Raw bytes work without a file, but carry no name to infer from.
expect_error(llm.api::llm_image(data = png_bytes), "`mime` is required")
expect_identical(llm.api::llm_image(data = png_bytes, mime = "image/png")$data,
                 jsonlite::base64_enc(png_bytes))

# Newlines are stripped from the encoding. jsonlite::base64_enc() wraps
# at 72 columns, and a data URL with a line break in it is rejected as
# an invalid base64 value -- an error that names the field rather than
# the newlines, which is a slow thing to work out from the outside.
local({
    big <- as.raw(rep(1:255, length.out = 4096))
    wrapped <- jsonlite::base64_enc(big)
    expect_true(grepl("\n", wrapped))
    enc <- llm.api::llm_image(data = big, mime = "image/png")$data
    expect_false(grepl("[\r\n]", enc))
    # Same bytes, just unwrapped: the strip must not lose any.
    expect_identical(enc, gsub("[\r\n]", "", wrapped))
    # And an already-base64 string is stripped on the same reasoning.
    expect_identical(
        llm.api::llm_image(data = wrapped, mime = "image/png")$data, enc)
})

# Exactly one source.
expect_error(llm.api::llm_image(), "exactly one")
expect_error(llm.api::llm_image(tmp_png, data = png_bytes), "exactly one")
expect_error(llm.api::llm_image(file.path(tempdir(), "nope.png")),
             "no such file")

# ---- llm_content ----

cnt <- llm.api::llm_content("what is this", img)
expect_inherits(cnt, "llm_content")
expect_identical(length(cnt), 2L)
expect_identical(cnt[[1L]]$text, "what is this")
expect_inherits(cnt[[2L]], "llm_image")

expect_error(llm.api::llm_content(), "at least one")
expect_error(llm.api::llm_content(42), "character scalar or an")

expect_true(llm.api::llm_has_image(cnt))
expect_true(llm.api::llm_has_image(img))
expect_false(llm.api::llm_has_image(llm.api::llm_content("just text")))
expect_false(llm.api::llm_has_image("just text"))
expect_false(llm.api::llm_has_image(NULL))

# ---- The three dialects ----
# One assertion per field each API actually reads. These are the shapes
# a wrong one would still serialize cleanly into.

msgs <- list(list(role = "user", content = cnt))

local({
    out <- llm.api:::.llm_blocks(msgs, "anthropic")
    b <- out[[1L]]$content
    expect_identical(b[[1L]], list(type = "text", text = "what is this"))
    expect_identical(b[[2L]]$type, "image")
    expect_identical(b[[2L]]$source$type, "base64")
    expect_identical(b[[2L]]$source$media_type, "image/png")
    expect_identical(b[[2L]]$source$data, img$data)
    # No data URL on this one: Anthropic takes the bare base64.
    expect_false(grepl("^data:", b[[2L]]$source$data))
})

local({
    out <- llm.api:::.llm_blocks(msgs, "openai")
    b <- out[[1L]]$content
    expect_identical(b[[1L]], list(type = "text", text = "what is this"))
    expect_identical(b[[2L]]$type, "image_url")
    # Chat Completions nests the URL in an object; Responses does not.
    expect_true(is.list(b[[2L]]$image_url))
    expect_identical(b[[2L]]$image_url$url,
                     paste0("data:image/png;base64,", img$data))
})

local({
    out <- llm.api:::.llm_blocks(msgs, "responses")
    b <- out[[1L]]$content
    # input_text, not text: the Responses API distinguishes what was
    # said to the model from what it said back.
    expect_identical(b[[1L]], list(type = "input_text",
                                   text = "what is this"))
    expect_identical(b[[2L]]$type, "input_image")
    expect_identical(b[[2L]]$image_url,
                     paste0("data:image/png;base64,", img$data))
})

# An assistant turn's text is output_text on the Responses dialect, and
# plain text everywhere else.
local({
    am <- list(list(role = "assistant",
                    content = llm.api::llm_content("I see a picture")))
    expect_identical(llm.api:::.llm_blocks(am, "responses")[[1L]]$content[[1L]]$type,
                     "output_text")
    expect_identical(llm.api:::.llm_blocks(am, "anthropic")[[1L]]$content[[1L]]$type,
                     "text")
})

# A message list with no llm_content in it comes back identical. This
# is what makes the translation safe to call unconditionally at every
# serialization point, which is why it is called there and not once at
# the top of chat().
local({
    plain <- list(list(role = "system", content = "be brief"),
                  list(role = "user", content = "hello"),
                  list(role = "user", content = list(list(type = "tool_result",
                                                          tool_use_id = "t1"))))
    for (d in c("anthropic", "openai", "responses")) {
        expect_identical(llm.api:::.llm_blocks(plain, d), plain)
    }
    expect_identical(llm.api:::.llm_blocks(list(), "openai"), list())
})

expect_error(llm.api:::.llm_blocks(msgs, "gemini"), "should be one of")

# ---- Every provider path translates ----
# The failure this guards is silent: jsonlite serializes an untranslated
# llm_content perfectly happily, into an array of {"text": "..."}
# objects that no provider understands and none of them error on. So
# each path is driven for real and the body inspected, rather than
# trusting that a .llm_blocks() call is present in the source.

ns <- asNamespace("llm.api")
orig_post_json <- get(".post_json", envir = ns, inherits = FALSE)
with_stubbed <- function(name, stub, expr) {
    orig <- get(name, envir = ns, inherits = FALSE)
    assignInNamespace(name, stub, ns = "llm.api")
    on.exit(assignInNamespace(name, orig, ns = "llm.api"), add = TRUE)
    force(expr)
}

# agent(): Anthropic, OpenAI, and Ollama all go out through .post_json.
for (spec in list(list(provider = "anthropic", dialect = "anthropic",
                       image_type = "image"),
                  list(provider = "openai", dialect = "openai",
                       image_type = "image_url"),
                  list(provider = "ollama", dialect = "openai",
                       image_type = "image_url"))) {
    local({
        s <- spec
        captured <- NULL
        stub <- function(url, body, headers) {
            captured <<- body
            if (identical(s$provider, "anthropic")) {
                list(content = list(list(type = "text", text = "ok")),
                     usage = list(input_tokens = 1L, output_tokens = 1L))
            } else {
                list(choices = list(list(
                    message = list(content = "ok", role = "assistant"),
                    finish_reason = "stop")),
                     usage = list(prompt_tokens = 1L, completion_tokens = 1L))
            }
        }
        with_stubbed(".post_json", stub,
            llm.api::agent(prompt = cnt, provider = s$provider,
                           model = "m", verbose = FALSE, max_turns = 1L))
        # The user turn is last: OpenAI and Ollama prepend a system one.
        turn <- captured$messages[[length(captured$messages)]]
        expect_identical(turn$role, "user")
        expect_identical(length(turn$content), 2L)
        expect_identical(turn$content[[2L]]$type, s$image_type)
        # And nothing classed survived to the serializer.
        expect_false(inherits(turn$content, "llm_content"))
    })
}

# The Codex/Responses path has its own converter, shared by four entry
# points. Driven through the body builder rather than through agent():
# .openai_codex_request() asks config$credentials() for headers before
# it ever reaches the POST, so a runner with no cached Codex token
# cannot get that far. (It got that far locally, on a token in my own
# cache, and failed on CI -- which is the whole argument for not
# testing a pure conversion through a credentialed transport.)
local({
    body <- llm.api:::.openai_codex_body(
        messages = list(list(role = "system", content = "sys"),
                        list(role = "user", content = cnt)),
        tools = list(), system = NULL, model = "gpt-5.5")
    turn <- body$input[[length(body$input)]]
    expect_identical(turn$role, "user")
    expect_identical(turn$content[[1L]]$type, "input_text")
    expect_identical(turn$content[[1L]]$text, "what is this")
    expect_identical(turn$content[[2L]]$type, "input_image")
    expect_identical(turn$content[[2L]]$image_url,
                     paste0("data:image/png;base64,", img$data))
    # The system turn beside it is untouched, and still a string.
    expect_identical(body$instructions, "sys")
})

# chat() does not go through .post_json -- it hands the JSON to curl
# itself -- so its two serializers are driven for real and the request
# body is read back off the handle. Stubbing the provider helpers
# instead would assert nothing about the thing under test.
capture_postfields <- function(expr) {
    cap <- NULL
    orig <- get("handle_setopt", envir = asNamespace("curl"),
                inherits = FALSE)
    stub <- function(handle, ..., .list = list()) {
        pf <- c(list(...), .list)$postfields
        if (!is.null(pf)) {
            cap <<- pf
        }
        invisible(handle)
    }
    assignInNamespace("handle_setopt", stub, ns = "curl")
    on.exit(assignInNamespace("handle_setopt", orig, ns = "curl"),
            add = TRUE)
    # The fetch that follows talks to a closed port, which is the
    # point: the body has already been built by then.
    tryCatch(force(expr), error = function(e) NULL)
    cap
}

local({
    # A closed port, so the request fails immediately after the body is
    # assembled rather than reaching anything.
    cfg <- list(provider = "ollama", base_url = "http://127.0.0.1:1",
                chat_path = "/v1/chat/completions", api_key = NULL)
    json <- capture_postfields(
        llm.api:::.chat_openai_compatible(
            list(model = "m", messages = msgs), cfg, stream = FALSE))
    sent <- jsonlite::fromJSON(json, simplifyVector = FALSE)
    b <- sent$messages[[1L]]$content
    expect_identical(b[[1L]]$type, "text")
    expect_identical(b[[2L]]$type, "image_url")
    expect_identical(b[[2L]]$image_url$url,
                     paste0("data:image/png;base64,", img$data))
})

local({
    cfg <- list(provider = "anthropic", base_url = "http://127.0.0.1:1",
                chat_path = "/v1/messages", api_key = "k")
    json <- capture_postfields(
        llm.api:::.chat_anthropic(list(model = "m", messages = msgs), cfg,
                                  stream = FALSE))
    sent <- jsonlite::fromJSON(json, simplifyVector = FALSE)
    b <- sent$messages[[1L]]$content
    expect_identical(b[[1L]]$type, "text")
    expect_identical(b[[2L]]$type, "image")
    expect_identical(b[[2L]]$source$media_type, "image/png")
    expect_identical(b[[2L]]$source$data, img$data)
})

# Moonshot's web-search loop rebuilds the request itself rather than
# reusing the chat-completions body, so it is its own path.
local({
    captured <- NULL
    stub <- function(url, body, headers) {
        captured <<- body
        list(choices = list(list(message = list(content = "ok",
                                                role = "assistant"),
                                 finish_reason = "stop")),
             usage = list(prompt_tokens = 1L, completion_tokens = 1L))
    }
    cfg <- list(provider = "moonshot", base_url = "http://127.0.0.1:1",
                chat_path = "/v1/chat/completions", api_key = "k")
    with_stubbed(".post_json", stub,
        llm.api:::.chat_moonshot_websearch(
            list(model = "m", messages = msgs, web_search = TRUE), cfg,
            stream = FALSE))
    expect_identical(captured$messages[[1L]]$content[[2L]]$type, "image_url")
})

# The guard: a provider path that forgets to translate is an error at
# the boundary rather than a strange answer from the model.
expect_error(llm.api:::.llm_assert_translated(msgs, "the request body"),
             "untranslated")
expect_true(llm.api:::.llm_assert_translated(list(), "x"))
expect_true(llm.api:::.llm_assert_translated(
    list(list(role = "user", content = "hi")), "x"))

# And it is wired into both shared POST helpers, not merely defined.
expect_error(orig_post_json("http://127.0.0.1:1/x",
                            list(messages = msgs), character()),
             "untranslated")
expect_error(llm.api:::.openai_codex_post_sse("http://127.0.0.1:1/x",
                                              list(input = msgs), character()),
             "untranslated")

unlink(tmp_png)
