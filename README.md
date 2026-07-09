# llm.api

Minimal-dependency LLM chat interface. Part of [cornyverse](https://github.com/cornball-ai).

## Exports

| Function | Purpose |
|----------|---------|
| `chat(prompt, model)` | Chat with any LLM |
| `chat_openai(prompt)` | OpenAI GPT models |
| `chat_openai_codex(prompt)` | OpenAI Codex via ChatGPT subscription auth |
| `chat_claude(prompt)` | Anthropic Claude (API key) |
| `chat_claude_oauth(prompt)` | Claude on a Claude subscription (OAuth) |
| `chat_ollama(prompt)` | Local Ollama server |
| `list_ollama_models()` | List Ollama models |
| `llm_base(url)` | Set API endpoint |
| `llm_key(key)` | Set API key |

## Providers

- **openai**: GPT-4o, GPT-4o-mini, o1, o3
- **anthropic**: Claude (Sonnet, Haiku) via an API key
- **anthropic_claude**: Claude on a Claude Pro/Max subscription (OAuth, no API key)
- **moonshot**: Kimi K2 via Moonshot's OpenAI-compatible API
- **openai_codex**: Codex Responses via ChatGPT subscription OAuth
- **ollama**: Llama 3.2, Mistral, Gemma, Phi, Qwen (via server)
- **openai_compatible**: any OpenAI-compatible endpoint (OpenRouter, DeepSeek, a local proxy, a corporate gateway) via a custom base URL

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

# Claude subscription-backed provider (log in once; see below)
chat_claude_oauth("Write a haiku about R")
chat("Refactor this loop", provider = "anthropic_claude")

# Any OpenAI-compatible endpoint via a custom base URL (see below)
llm_base("https://openrouter.ai/api/v1")
chat("Refactor this loop", provider = "openai_compatible",
     model = "meta-llama/llama-3-70b-instruct")

# Provider-native web search (the model searches on its own when useful)
chat("What changed in the latest R release?", web_search = TRUE)

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

### Claude (Claude subscription)

The `anthropic_claude` provider drives Claude on a Claude Pro/Max
subscription instead of an API key, the same OAuth pattern as
`openai_codex`. The token is cached and refreshed by
[tinyoauth](https://github.com/cornball-ai/tinyoauth), so you log in
once and it persists across R sessions.

```r
# One-time: prints an authorization URL. Approve it and paste the code back.
claude_oauth_login()

# Thereafter, just use the provider; credentials come from the cache
# and refresh automatically.
chat_claude_oauth("Write a haiku about R")
chat("Refactor this", provider = "anthropic_claude")
```

To use an externally-obtained token instead of logging in, set
`ANTHROPIC_CLAUDE_ACCESS_TOKEN`; it overrides the cache.

### OpenAI-compatible endpoints

The `openai_compatible` provider targets any endpoint that speaks the
OpenAI chat-completions format: OpenRouter, DeepSeek, DeepInfra, a local
proxy, or a corporate gateway. Set the endpoint with `llm_base()` or the
`OPENAI_COMPATIBLE_BASE_URL` environment variable; `/chat/completions` is
appended, so include whatever `/v1` prefix the gateway expects. The model
id is passed through untouched and is required (there is no default).

```r
llm_base("https://openrouter.ai/api/v1")
chat("Write a haiku about R",
     provider = "openai_compatible",
     model = "meta-llama/llama-3-70b-instruct")
```

The API key comes from `OPENAI_COMPATIBLE_API_KEY`, falling back to
`OPENAI_API_KEY`; a keyless internal gateway (no `Authorization` header)
works with neither set. A missing base URL or model fails fast with setup
instructions rather than a curl error.

## Web search

`chat()` and `agent()` take a `web_search` argument (`FALSE` by
default, `TRUE`, or a list of `allowed_domains` / `user_location`
options) that runs the model's own server-side search rather than a
separate search API. The model decides when to search; the result
carries `citations` and `searches`.

It's wired for the hosted providers: `openai` / `openai_codex` (the
Responses `web_search` tool), `anthropic` / `anthropic_claude` (the
Messages `web_search` tool), and `moonshot` (its `$web_search`
builtin). Other providers ignore it with a warning.

```r
res <- chat("What changed in the latest R release?", web_search = TRUE)
res$citations
```

## Dependencies

`curl`, `jsonlite`, and
[tinyoauth](https://github.com/cornball-ai/tinyoauth) (for Codex device
login and token caching). No tidyverse, no compiled code.
