# Test provider detection and configuration

# --- Setup: save and restore options ---
old_opts <- options(llm.api.api_base = NULL, llm.api.api_key = NULL)
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

# Ollama models
expect_equal(llm.api:::.detect_provider("llama3.2"), "ollama")
expect_equal(llm.api:::.detect_provider("mistral"), "ollama")
expect_equal(llm.api:::.detect_provider("phi3"), "ollama")
expect_equal(llm.api:::.detect_provider("qwen2"), "ollama")

# Local GGUF files
expect_equal(llm.api:::.detect_provider("model.gguf"), "local")
expect_equal(llm.api:::.detect_provider("/path/to/model.GGUF"), "local")

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

# Reset
options(llm.api.api_base = NULL)

# --- .get_provider_config() ---

# OpenAI config
cfg <- llm.api:::.get_provider_config("openai")
expect_equal(cfg$base_url, "https://api.openai.com")
expect_equal(cfg$chat_path, "/v1/chat/completions")
expect_equal(cfg$default_model, "gpt-4o-mini")

# Anthropic config
cfg <- llm.api:::.get_provider_config("anthropic")
expect_equal(cfg$base_url, "https://api.anthropic.com")
expect_equal(cfg$chat_path, "/v1/messages")
expect_equal(cfg$default_model, "claude-3-5-sonnet-latest")

# Moonshot config
cfg <- llm.api:::.get_provider_config("moonshot")
expect_equal(cfg$base_url, "https://api.moonshot.ai")
expect_equal(cfg$chat_path, "/v1/chat/completions")
expect_equal(cfg$default_model, "kimi-k2")

# Ollama config
cfg <- llm.api:::.get_provider_config("ollama")
expect_equal(cfg$base_url, "http://localhost:11434")
expect_equal(cfg$chat_path, "/v1/chat/completions")
expect_equal(cfg$default_model, "llama3.2")
expect_null(cfg$api_key)

# Unknown provider errors
expect_error(llm.api:::.get_provider_config("unknown"), pattern = "Unknown provider")
