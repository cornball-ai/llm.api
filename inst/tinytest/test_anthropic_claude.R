# Anthropic Claude subscription (OAuth) provider tests. Offline: credentials are
# exercised with an explicit/env token, no network or tinyoauth cache hit.

ns <- asNamespace("llm.api")

old_env <- Sys.getenv("ANTHROPIC_CLAUDE_ACCESS_TOKEN", unset = NA_character_)
on.exit({
    if (is.na(old_env)) {
        Sys.unsetenv("ANTHROPIC_CLAUDE_ACCESS_TOKEN")
    } else {
        Sys.setenv(ANTHROPIC_CLAUDE_ACCESS_TOKEN = old_env)
    }
}, add = TRUE)
Sys.unsetenv("ANTHROPIC_CLAUDE_ACCESS_TOKEN")

# --- .is_anthropic covers both API-key and OAuth providers ---
expect_true(ns$.is_anthropic("anthropic"))
expect_true(ns$.is_anthropic("anthropic_claude"))
expect_false(ns$.is_anthropic("openai"))

# --- provider config ---
cfg <- llm.api:::.get_provider_config("anthropic_claude")
expect_equal(cfg$provider, "anthropic_claude")
expect_equal(cfg$base_url, "https://api.anthropic.com")
expect_equal(cfg$chat_path, "/v1/messages")
expect_equal(cfg$default_model, "claude-sonnet-4-6")
expect_true(is.function(cfg$credentials))
expect_equal(provider_default_model("anthropic_claude"), "claude-sonnet-4-6")

# --- header selection: API key vs OAuth ---
api_headers <- ns$.anthropic_headers(list(api_key = "sk-test", credentials = NULL))
expect_equal(unname(api_headers[["x-api-key"]]), "sk-test")
expect_true(is.na(api_headers["Authorization"]))
expect_equal(unname(api_headers[["anthropic-version"]]), "2023-06-01")

creds <- anthropic_claude_credentials(access_token = "tok-123")
oauth_headers <- ns$.anthropic_headers(list(api_key = NULL, credentials = creds))
expect_equal(unname(oauth_headers[["Authorization"]]), "Bearer tok-123")
expect_equal(unname(oauth_headers[["anthropic-beta"]]), "oauth-2025-04-20")
expect_true(is.na(oauth_headers["x-api-key"]))

# --- credentials: explicit token, env override, and the headers shape ---
h <- anthropic_claude_credentials(access_token = "tok-abc")()
expect_equal(h$Authorization, "Bearer tok-abc")
expect_equal(h[["anthropic-beta"]], "oauth-2025-04-20")

Sys.setenv(ANTHROPIC_CLAUDE_ACCESS_TOKEN = "env-tok")
expect_equal(anthropic_claude_credentials()()$Authorization, "Bearer env-tok")
Sys.unsetenv("ANTHROPIC_CLAUDE_ACCESS_TOKEN")

# --- subscription usage prices like the API provider (same shape) ---
u <- list(input_tokens = 1000L, output_tokens = 500L)
expect_equal(usage_cost("claude-sonnet-4-6", "anthropic_claude", u),
             usage_cost("claude-sonnet-4-6", "anthropic", u))

# --- regression: every provider stays discoverable via formals() ---
# Downstream packages (e.g. corteza) enumerate providers with
# eval(formals(llm.api::agent)$provider). A scalar default silently drops
# every provider but the first, so the literal choice vector must stay.
all_providers <- c("anthropic", "anthropic_claude", "openai", "moonshot",
                   "openai_codex", "ollama")
expect_true(all(all_providers %in% eval(formals(agent)$provider)))
expect_true(all(all_providers %in% eval(formals(create_agent)$provider)))
expect_true("anthropic_claude" %in% eval(formals(chat)$provider))
expect_true("anthropic_claude" %in% eval(formals(chat_session)$provider))

# --- regression: anthropic_claude is web-search enabled ---
# It shares the Anthropic Messages path, so chat()/agent() must not warn
# and reset web_search = FALSE for it before the request is built.
expect_true("anthropic_claude" %in% ns$.web_search_providers())

# --- regression: subscription OAuth needs the Claude Code identity ---
# Anthropic rejects an OAuth request (429) unless the first system block is
# the Claude Code identity. The API-key path must stay byte-identical.
id <- "You are Claude Code, Anthropic's official CLI for Claude."
# OAuth, no caller system -> identity is the only block.
s1 <- ns$.anthropic_system(NULL, "none", oauth = TRUE)
expect_equal(length(s1), 1L)
expect_equal(s1[[1]]$text, id)
# OAuth, with a caller system -> identity first, caller second.
s2 <- ns$.anthropic_system("Be terse.", "none", oauth = TRUE)
expect_equal(s2[[1]]$text, id)
expect_equal(s2[[2]]$text, "Be terse.")
# OAuth + cache -> cache_control rides the last block.
s3 <- ns$.anthropic_system("x", "5m", oauth = TRUE)
expect_equal(s3[[length(s3)]]$cache_control$type, "ephemeral")
# API-key path unchanged: plain string with no cache, NULL with no system.
expect_equal(ns$.anthropic_system("hello", "none", oauth = FALSE), "hello")
expect_null(ns$.anthropic_system(NULL, "none", oauth = FALSE))
