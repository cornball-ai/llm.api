# Anthropic Claude subscription (OAuth) provider tests. Offline: credentials are
# exercised with an explicit/env token, no network or tinyoauth cache hit.

ns <- asNamespace("llm.api")

old_env <- Sys.getenv("ANTHROPIC_OAUTH_ACCESS_TOKEN", unset = NA_character_)
on.exit({
    if (is.na(old_env)) {
        Sys.unsetenv("ANTHROPIC_OAUTH_ACCESS_TOKEN")
    } else {
        Sys.setenv(ANTHROPIC_OAUTH_ACCESS_TOKEN = old_env)
    }
}, add = TRUE)
Sys.unsetenv("ANTHROPIC_OAUTH_ACCESS_TOKEN")

# --- .is_anthropic covers both API-key and OAuth providers ---
expect_true(ns$.is_anthropic("anthropic"))
expect_true(ns$.is_anthropic("anthropic_oauth"))
expect_false(ns$.is_anthropic("openai"))

# --- provider config ---
cfg <- llm.api:::.get_provider_config("anthropic_oauth")
expect_equal(cfg$provider, "anthropic_oauth")
expect_equal(cfg$base_url, "https://api.anthropic.com")
expect_equal(cfg$chat_path, "/v1/messages")
expect_equal(cfg$default_model, "claude-sonnet-4-6")
expect_true(is.function(cfg$credentials))
expect_equal(provider_default_model("anthropic_oauth"), "claude-sonnet-4-6")

# --- header selection: API key vs OAuth ---
api_headers <- ns$.anthropic_headers(list(api_key = "sk-test", credentials = NULL))
expect_equal(unname(api_headers[["x-api-key"]]), "sk-test")
expect_true(is.na(api_headers["Authorization"]))
expect_equal(unname(api_headers[["anthropic-version"]]), "2023-06-01")

creds <- anthropic_oauth_credentials(access_token = "tok-123")
oauth_headers <- ns$.anthropic_headers(list(api_key = NULL, credentials = creds))
expect_equal(unname(oauth_headers[["Authorization"]]), "Bearer tok-123")
expect_equal(unname(oauth_headers[["anthropic-beta"]]), "oauth-2025-04-20")
expect_true(is.na(oauth_headers["x-api-key"]))

# --- credentials: explicit token, env override, and the headers shape ---
h <- anthropic_oauth_credentials(access_token = "tok-abc")()
expect_equal(h$Authorization, "Bearer tok-abc")
expect_equal(h[["anthropic-beta"]], "oauth-2025-04-20")

Sys.setenv(ANTHROPIC_OAUTH_ACCESS_TOKEN = "env-tok")
expect_equal(anthropic_oauth_credentials()()$Authorization, "Bearer env-tok")
Sys.unsetenv("ANTHROPIC_OAUTH_ACCESS_TOKEN")

# --- subscription usage prices like the API provider (same shape) ---
u <- list(input_tokens = 1000L, output_tokens = 500L)
expect_equal(usage_cost("claude-sonnet-4-6", "anthropic_oauth", u),
             usage_cost("claude-sonnet-4-6", "anthropic", u))
