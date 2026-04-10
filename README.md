# llm.api

*"Llamar" is Spanish for "to call"*

Minimal-dependency LLM chat interface. Part of [cornyverse](https://github.com/cornball-ai).

## Exports

| Function | Purpose |
|----------|---------|
| `chat(prompt, model)` | Chat with any LLM |
| `chat_openai(prompt)` | OpenAI GPT models |
| `chat_claude(prompt)` | Anthropic Claude models |
| `chat_ollama(prompt)` | Local Ollama server |
| `chat_local(prompt, model)` | Direct llama.cpp via localLLM |
| `list_local_models()` | Find GGUF files |
| `list_ollama_models()` | List Ollama models |
| `llm_base(url)` | Set API endpoint |
| `llm_key(key)` | Set API key |

## Providers

- **openai**: GPT-4o, GPT-4o-mini, o1, o3
- **anthropic**: Claude 3.5 Sonnet, Claude 3.5 Haiku
- **moonshot**: Kimi K2 via Moonshot's OpenAI-compatible API
- **ollama**: Llama 3.2, Mistral, Gemma, Phi, Qwen (via server)
- **local**: Any GGUF model via llama.cpp (no server needed)

## Usage

```r
# Auto-detect provider from model
chat("Hello", model = "gpt-4o")
chat("Hello", model = "claude-3-5-sonnet-latest")
chat("Hello", model = "kimi-k2")

# Use convenience wrappers
chat_ollama("What is R?")
chat_claude("Explain machine learning")

# Explicit Moonshot/Kimi provider
chat("Write a fast parser in R", provider = "moonshot", model = "kimi-k2")

# Direct local inference (no server)
chat_local("Explain R", model = "~/models/llama-3.2-1b.gguf")
chat("Hello", model = "model.gguf")  # Auto-detects local

# Conversation history
result <- chat("Hi, I'm Troy")
chat("What's my name?", history = result$history)

# Streaming
chat("Write a story", stream = TRUE)
```

Set `MOONSHOT_API_KEY` to use Moonshot/Kimi without overriding your
OpenAI credentials.

## Dependencies

- **Required**: `curl`, `jsonlite`
- **Optional**: `localLLM` (for direct llama.cpp inference)
