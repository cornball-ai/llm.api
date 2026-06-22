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
