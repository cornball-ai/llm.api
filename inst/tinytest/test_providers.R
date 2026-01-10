# Test provider detection and configuration

# --- Setup: save and restore options ---
old_opts <- options(llamaR.api_base = NULL, llamaR.api_key = NULL)
on.exit(options(old_opts), add = TRUE)

# --- .detect_provider() from model name ---

# OpenAI models
expect_equal(llamaR:::.detect_provider("gpt-4o"), "openai")
expect_equal(llamaR:::.detect_provider("gpt-4o-mini"), "openai")
expect_equal(llamaR:::.detect_provider("o1-preview"), "openai")

# Anthropic models
expect_equal(llamaR:::.detect_provider("claude-3-5-sonnet-latest"), "anthropic")
expect_equal(llamaR:::.detect_provider("claude-3-opus"), "anthropic")

# Ollama models
expect_equal(llamaR:::.detect_provider("llama3.2"), "ollama")
expect_equal(llamaR:::.detect_provider("mistral"), "ollama")
expect_equal(llamaR:::.detect_provider("phi3"), "ollama")
expect_equal(llamaR:::.detect_provider("qwen2"), "ollama")

# Local GGUF files
expect_equal(llamaR:::.detect_provider("model.gguf"), "local")
expect_equal(llamaR:::.detect_provider("/path/to/model.GGUF"), "local")

# Default to openai for unknown
expect_equal(llamaR:::.detect_provider("unknown-model"), "openai")
expect_equal(llamaR:::.detect_provider(NULL), "openai")

# --- .detect_provider() from base URL ---

llm_base("http://localhost:11434")
expect_equal(llamaR:::.detect_provider(NULL), "ollama")

llm_base("https://api.anthropic.com")
expect_equal(llamaR:::.detect_provider(NULL), "anthropic")

llm_base("https://api.openai.com")
expect_equal(llamaR:::.detect_provider(NULL), "openai")

# Reset
options(llamaR.api_base = NULL)

# --- .get_provider_config() ---

# OpenAI config
cfg <- llamaR:::.get_provider_config("openai")
expect_equal(cfg$base_url, "https://api.openai.com")
expect_equal(cfg$chat_path, "/v1/chat/completions")
expect_equal(cfg$default_model, "gpt-4o-mini")

# Anthropic config
cfg <- llamaR:::.get_provider_config("anthropic")
expect_equal(cfg$base_url, "https://api.anthropic.com")
expect_equal(cfg$chat_path, "/v1/messages")
expect_equal(cfg$default_model, "claude-3-5-sonnet-latest")

# Ollama config
cfg <- llamaR:::.get_provider_config("ollama")
expect_equal(cfg$base_url, "http://localhost:11434")
expect_equal(cfg$chat_path, "/v1/chat/completions")
expect_equal(cfg$default_model, "llama3.2")
expect_null(cfg$api_key)

# Unknown provider errors
expect_error(llamaR:::.get_provider_config("unknown"), pattern = "Unknown provider")
