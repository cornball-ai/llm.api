# llamaR

Minimal-dependency LLM chat interface. Part of [cornyverse](~/cornyverse).

## Exports

| Function | Purpose |
|----------|---------|
| `chat(prompt, model)` | Chat with any LLM |
| `chat_openai(prompt)` | OpenAI GPT models |
| `chat_claude(prompt)` | Anthropic Claude models |
| `chat_ollama(prompt)` | Local Ollama models |
| `llm_base(url)` | Set API endpoint |
| `llm_key(key)` | Set API key |

## Providers

- **openai**: GPT-4o, GPT-4o-mini, o1, o3
- **anthropic**: Claude 3.5 Sonnet, Claude 3.5 Haiku
- **ollama**: Llama 3.2, Mistral, Gemma, Phi, Qwen

## Usage

```r
# Auto-detect provider from model
chat("Hello", model = "gpt-4o")
chat("Hello", model = "claude-3-5-sonnet-latest")

# Use convenience wrappers
chat_ollama("What is R?")
chat_claude("Explain machine learning")

# Conversation history
result <- chat("Hi, I'm Troy")
chat("What's my name?", history = result$history)

# Streaming
chat("Write a story", stream = TRUE)
```

## Dependencies

Only `curl` and `jsonlite` - no tidyverse, no R6, no S7.
