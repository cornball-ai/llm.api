# Test provider detection and configuration

# --- Setup: save and restore options ---
old_opts <- options(llm.api_base = NULL, llm.api_key = NULL, llm.api.api_base = NULL, llm.api.api_key = NULL)
on.exit(options(old_opts), add = TRUE)

# --- .detect_provider() from model name ---

# OpenAI models
expect_equal(llm.api:::.detect_provider("gpt-4o"), "openai")
expect_equal(llm.api:::.detect_provider("gpt-4o-mini"), "openai")
expect_equal(llm.api:::.detect_provider("o1-preview"), "openai")

# Anthropic models
expect_equal(llm.api:::.detect_provider("claude-3-5-sonnet-latest"), "anthropic")
expect_equal(llm.api:::.detect_provider("claude-3-opus"), "anthropic")

# Moonshot / Kimi models
expect_equal(llm.api:::.detect_provider("kimi-k2"), "moonshot")
expect_equal(llm.api:::.detect_provider("kimi-k2-turbo-preview"), "moonshot")
expect_equal(llm.api:::.detect_provider("moonshot-v1-8k"), "moonshot")

# Google / Gemini models. "gemma" stays local: ^gemini must not take it.
expect_equal(llm.api:::.detect_provider("gemini-3.5-flash"), "google")
expect_equal(llm.api:::.detect_provider("gemini-3.1-pro-preview"), "google")
expect_equal(llm.api:::.detect_provider("gemma3"), "ollama")

# Ollama models
expect_equal(llm.api:::.detect_provider("llama3.2"), "ollama")
expect_equal(llm.api:::.detect_provider("mistral"), "ollama")
expect_equal(llm.api:::.detect_provider("phi3"), "ollama")
expect_equal(llm.api:::.detect_provider("qwen2"), "ollama")

# Default to openai for unknown
expect_equal(llm.api:::.detect_provider("unknown-model"), "openai")
expect_equal(llm.api:::.detect_provider(NULL), "openai")

# --- .detect_provider() from base URL ---

llm_base("http://localhost:11434")
expect_equal(llm.api:::.detect_provider(NULL), "ollama")

llm_base("https://api.anthropic.com")
expect_equal(llm.api:::.detect_provider(NULL), "anthropic")

llm_base("https://api.openai.com")
expect_equal(llm.api:::.detect_provider(NULL), "openai")

llm_base("https://api.moonshot.ai")
expect_equal(llm.api:::.detect_provider(NULL), "moonshot")

# Gemini's compat base contains "openai" in its path; google must win.
llm_base("https://generativelanguage.googleapis.com/v1beta/openai")
expect_equal(llm.api:::.detect_provider(NULL), "google")

# Reset
options(llm.api_base = NULL, llm.api.api_base = NULL)

# --- .get_provider_config() ---

# OpenAI config
cfg <- llm.api:::.get_provider_config("openai")
expect_equal(cfg$base_url, "https://api.openai.com")
expect_equal(cfg$chat_path, "/v1/chat/completions")
expect_equal(cfg$default_model, "gpt-6.1-sol")

# Anthropic config
cfg <- llm.api:::.get_provider_config("anthropic")
expect_equal(cfg$base_url, "https://api.anthropic.com")
expect_equal(cfg$chat_path, "/v1/messages")
expect_equal(cfg$default_model, "claude-sonnet-4-6")

# Moonshot config
cfg <- llm.api:::.get_provider_config("moonshot")
expect_equal(cfg$base_url, "https://api.moonshot.ai")
expect_equal(cfg$chat_path, "/v1/chat/completions")
expect_equal(cfg$default_model, "kimi-k2.5")

# Google config: the base carries the /v1beta/openai prefix so the
# bare "/chat/completions" path appends to it.
cfg <- llm.api:::.get_provider_config("google")
expect_equal(cfg$base_url,
             "https://generativelanguage.googleapis.com/v1beta/openai")
expect_equal(cfg$chat_path, "/chat/completions")
expect_equal(cfg$default_model, "gemini-3.5-flash")

# Ollama config
cfg <- llm.api:::.get_provider_config("ollama")
expect_equal(cfg$base_url, "http://localhost:11434")
expect_equal(cfg$chat_path, "/v1/chat/completions")
expect_equal(cfg$default_model, "qwen3.5:9b")
expect_null(cfg$api_key)

# Unknown provider errors
expect_error(llm.api:::.get_provider_config("unknown"), pattern = "Unknown provider")

# provider_default_model() exposes the default model id for each
# supported provider so client code (e.g., status lines) can resolve it
# upfront without reaching into internals.
expect_equal(provider_default_model("openai"), "gpt-6.1-sol")
expect_equal(provider_default_model("anthropic"), "claude-sonnet-4-6")
expect_equal(provider_default_model("moonshot"), "kimi-k2.5")
expect_equal(provider_default_model("google"), "gemini-3.5-flash")
expect_equal(provider_default_model("ollama"), "qwen3.5:9b")
expect_error(provider_default_model("nonsense"), pattern = "Unknown provider")

# --- One source for default models ---
#
# The provider table names each default. The convenience wrappers repeat
# it in their signatures, so pin every one to the table: a default
# changed in one place and not the other fails here, not downstream.
local({
    wrappers <- list(
        chat_openai = "openai", chat_claude = "anthropic",
        chat_claude_oauth = "anthropic_claude",
        chat_openai_codex = "openai_codex", chat_ollama = "ollama",
        chat_session_openai = "openai",
        chat_session_openai_codex = "openai_codex",
        chat_session_anthropic = "anthropic", chat_session_ollama = "ollama")
    for (fn in names(wrappers)) {
        expect_identical(
            formals(getExportedValue("llm.api", fn))$model,
            provider_default_model(wrappers[[fn]]), info = fn)
    }
})
