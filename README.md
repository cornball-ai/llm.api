# llm.api

Minimal-dependency LLM chat interface. Part of [cornyverse](https://github.com/cornball-ai).

## Exports

| Function | Purpose |
|----------|---------|
| `chat(prompt, model)` | Chat with any LLM |
| `chat_openai(prompt)` | OpenAI GPT models |
| `chat_openai_codex(prompt)` | OpenAI Codex via ChatGPT subscription auth |
| `chat_claude(prompt)` | Anthropic Claude models |
| `chat_ollama(prompt)` | Local Ollama server |
| `list_ollama_models()` | List Ollama models |
| `llm_base(url)` | Set API endpoint |
| `llm_key(key)` | Set API key |

## Providers

- **openai**: GPT-4o, GPT-4o-mini, o1, o3
- **anthropic**: Claude 3.5 Sonnet, Claude 3.5 Haiku
- **moonshot**: Kimi K2 via Moonshot's OpenAI-compatible API
- **openai_codex**: Codex Responses via ChatGPT subscription OAuth
- **ollama**: Llama 3.2, Mistral, Gemma, Phi, Qwen (via server)

## Usage

```r
# Auto-detect provider from model
chat("Hello", model = "gpt-5.4-mini")
chat("Hello", model = "claude-3-5-sonnet-latest")
chat("Hello", model = "kimi-k2.5")

# Use convenience wrappers
chat_ollama("What is R?")
chat_claude("Explain machine learning")

# Explicit Moonshot/Kimi provider
chat("Write a fast parser in R", provider = "moonshot", model = "kimi-k2.5")

# ChatGPT subscription-backed Codex provider (log in once; see below)
chat_openai_codex("Write a small R function")
chat("Refactor this loop", provider = "openai_codex", model = "gpt-5.5")

# Conversation history
result <- chat("Hi, I'm Troy")
chat("What's my name?", history = result$history)

# Streaming
chat("Write a story", stream = TRUE)
```

Set `MOONSHOT_API_KEY` to use Moonshot/Kimi without overriding your
OpenAI credentials.

### OpenAI Codex (ChatGPT subscription)

The `openai_codex` provider talks to Codex using your ChatGPT
subscription instead of an API key. Authentication is a one-time device
login; the token is cached and refreshed by
[tinyoauth](https://github.com/cornball-ai/tinyoauth), so you log in
once and it persists across R sessions.

```r
# One-time: device-code login. Prints a URL + code to authorize in a
# browser. The token is cached under tools::R_user_dir("tinyoauth").
openai_codex_login()

# Thereafter, just use the provider; credentials come from the cache
# and refresh automatically.
chat_openai_codex("Write a small R function")
chat("Refactor this", provider = "openai_codex", model = "gpt-5.5")
```

Models: `gpt-5.5` (default), `gpt-5.4`, `gpt-5.4-mini`,
`gpt-5.3-codex-spark`.

To use an externally-obtained token instead of logging in, set
`OPENAI_CODEX_ACCESS_TOKEN` (and optionally `OPENAI_CODEX_ACCOUNT_ID`);
these override the cache.

## Dependencies

`curl`, `jsonlite`, and
[tinyoauth](https://github.com/cornball-ai/tinyoauth) (for Codex device
login and token caching). No tidyverse, no compiled code.
