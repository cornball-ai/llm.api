# openai_compatible: generic OpenAI-compatible gateway provider
# (OpenRouter, DeepSeek, corporate proxies). All tests are offline:
# they cover config resolution and the fail-fast guards that run
# before any request is attempted.

# --- Setup: neutralize ambient config so resolution is deterministic ---
old_opts <- options(llm.api.api_base = NULL, llm.api.api_key = NULL)
old_base_env <- Sys.getenv("OPENAI_COMPATIBLE_BASE_URL", NA)
old_key_env <- Sys.getenv("OPENAI_COMPATIBLE_API_KEY", NA)
old_openai_key <- Sys.getenv("OPENAI_API_KEY", NA)
Sys.unsetenv("OPENAI_COMPATIBLE_BASE_URL")
Sys.unsetenv("OPENAI_COMPATIBLE_API_KEY")
Sys.unsetenv("OPENAI_API_KEY")

# --- .get_provider_config() resolution ---

# Nothing set anywhere: no base URL, no default model, empty key
cfg <- llm.api:::.get_provider_config("openai_compatible")
expect_equal(cfg$provider, "openai_compatible")
expect_null(cfg$base_url)
expect_equal(cfg$chat_path, "/chat/completions")
expect_null(cfg$default_model)
expect_equal(cfg$api_key, "")

# Env var supplies the base; a trailing slash is stripped
Sys.setenv(OPENAI_COMPATIBLE_BASE_URL = "https://openrouter.ai/api/v1/")
cfg <- llm.api:::.get_provider_config("openai_compatible")
expect_equal(cfg$base_url, "https://openrouter.ai/api/v1")

# llm_base() wins over the env var
llm_base("https://gateway.example.com/v1")
cfg <- llm.api:::.get_provider_config("openai_compatible")
expect_equal(cfg$base_url, "https://gateway.example.com/v1")
options(llm.api.api_base = NULL)
Sys.unsetenv("OPENAI_COMPATIBLE_BASE_URL")

# --- key resolution: OPENAI_COMPATIBLE_API_KEY first, then OPENAI_API_KEY ---

Sys.setenv(OPENAI_API_KEY = "sk-openai-fallback")
cfg <- llm.api:::.get_provider_config("openai_compatible")
expect_equal(cfg$api_key, "sk-openai-fallback")

Sys.setenv(OPENAI_COMPATIBLE_API_KEY = "sk-gateway")
cfg <- llm.api:::.get_provider_config("openai_compatible")
expect_equal(cfg$api_key, "sk-gateway")

Sys.unsetenv("OPENAI_COMPATIBLE_API_KEY")
Sys.unsetenv("OPENAI_API_KEY")

# --- fail-fast guards, no network ---

# No base URL: chat() and agent() error with setup instructions
expect_error(chat("hi", provider = "openai_compatible", model = "some/model"),
             pattern = "needs a base URL")
expect_error(agent("hi", provider = "openai_compatible", model = "some/model"),
             pattern = "needs a base URL")

# Base set but no model: there is no default to fall back to
llm_base("https://gateway.example.com/v1")
expect_error(chat("hi", provider = "openai_compatible"),
             pattern = "no default model")
expect_error(agent("hi", provider = "openai_compatible"),
             pattern = "no default model")
options(llm.api.api_base = NULL)

# provider_default_model() reports the absence of a default as NULL
expect_null(provider_default_model("openai_compatible"))

# The guard is inert for every other provider
expect_null(llm.api:::.check_openai_compatible(
    llm.api:::.get_provider_config("ollama"), NULL))

# --- Cleanup ---
options(old_opts)
if (!is.na(old_base_env)) Sys.setenv(OPENAI_COMPATIBLE_BASE_URL = old_base_env)
if (!is.na(old_key_env)) Sys.setenv(OPENAI_COMPATIBLE_API_KEY = old_key_env)
if (!is.na(old_openai_key)) Sys.setenv(OPENAI_API_KEY = old_openai_key)
