# Anthropic provider-native web search: offline tests for the tool builder and
# the citation/search block parser (the live call needs a key + network).
ns <- asNamespace("llm.api")
`%||%` <- function(x, y) if (is.null(x)) y else x

expect_true("anthropic" %in% ns$.web_search_providers())

# tool builder: off -> NULL; on -> basic web_search_20250305; options mapped
expect_null(ns$.anthropic_web_search_tool(FALSE))
expect_null(ns$.anthropic_web_search_tool(NULL))
t <- ns$.anthropic_web_search_tool(TRUE)
expect_equal(t$type, "web_search_20250305")
expect_equal(t$name, "web_search")
t2 <- ns$.anthropic_web_search_tool(list(max_uses = 3, allowed_domains = "r-project.org",
                                         blocked_domains = "x.com",
                                         user_location = list(type = "approximate")))
expect_equal(t2$max_uses, 3L)
expect_equal(t2$allowed_domains[[1]], "r-project.org")
expect_equal(t2$blocked_domains[[1]], "x.com")
expect_equal(t2$user_location$type, "approximate")

# block parser: query from server_tool_use, citations from text blocks
content <- list(
    list(type = "server_tool_use", name = "web_search", input = list(query = "R version")),
    list(type = "web_search_tool_result", content = list()),
    list(type = "text", text = "R 4.6.0",
         citations = list(list(url = "https://www.r-project.org/", title = "R"))),
    list(type = "text", text = "more", citations = list()))
info <- ns$.anthropic_search_blocks(content)
expect_equal(length(info$searches), 1L)
expect_equal(info$searches[[1]]$query, "R version")
expect_equal(length(info$citations), 1L)
expect_equal(info$citations[[1]]$url, "https://www.r-project.org/")

# no search blocks -> empty
empty <- ns$.anthropic_search_blocks(list(list(type = "text", text = "hi")))
expect_equal(length(empty$citations), 0L)
expect_equal(length(empty$searches), 0L)

# reply text: the API cuts a cited answer into text blocks at every
# citation boundary, mid-sentence. The pieces are one passage; the text
# before the search is a paragraph of its own. This is the block
# sequence of a real web-search reply.
join <- ns$.anthropic_join_text
types <- c("text", "server_tool_use", "web_search_tool_result", "text",
           "text", "text")
texts <- c("I'll search for the score.", NA, NA, "Based on the results, ",
           "the Braves are leading 5-0",
           ". The game is still being played.")
expect_identical(join(types, texts), paste0(
    "I'll search for the score.\n\n",
    "Based on the results, the Braves are leading 5-0",
    ". The game is still being played."))
# No stray line holds only punctuation.
expect_false(any(grepl("^[.,]", strsplit(join(types, texts), "\n")[[1]])))
# One text block, or none.
expect_identical(join("text", "hi"), "hi")
expect_identical(join(character(), character()), "")
expect_identical(join(c("tool_use", "thinking"), c(NA, NA)), "")
# Text around a tool call or a thinking block: separate paragraphs, and
# no more than one blank line whatever the first piece ended with.
expect_identical(join(c("text", "tool_use", "text"), c("a\n", NA, "b")),
                 "a\n\nb")
expect_identical(join(c("thinking", "text", "thinking", "text"),
                      c(NA, "a", NA, "b")), "a\n\nb")
expect_identical(join(c("text", "text"), c("a", NA)), "a")

# chat()'s parser sees content either as a list or, when jsonlite
# simplifies it, as a data frame; both give the same joined text.
raw_json <- paste0(
    '{"content":[{"type":"text","text":"Before."},',
    '{"type":"server_tool_use","id":"s1","name":"web_search",',
    '"input":{"query":"q"}},',
    '{"type":"text","text":"It is "},',
    '{"type":"text","text":"5-0","citations":[{"url":"https://x.test"}]},',
    '{"type":"text","text":"."}]}')
as_df <- jsonlite::fromJSON(raw_json)$content
expect_true(is.data.frame(as_df))
expect_identical(join(as_df$type, as.character(as_df$text)),
                 "Before.\n\nIt is 5-0.")
as_list <- jsonlite::fromJSON(raw_json, simplifyVector = FALSE)$content
expect_identical(
    join(vapply(as_list, function(b) b$type, ""),
         vapply(as_list, function(b) as.character(b$text %||% NA_character_),
                "")),
    "Before.\n\nIt is 5-0.")
