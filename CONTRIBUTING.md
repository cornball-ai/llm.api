# Contributing to llm.api

## Adding a model

Models are loose. `chat()` and `agent()` pass `model` straight through to
the provider, so any id the provider accepts already works — there's no
allowlist to update. (corteza only validates `ollama` models, against the
running server.) Two things make a model first-class:

1. **Default model.** What a provider falls back to when `model` is unset
   is its `default_model` in `.get_provider_config()` (`R/providers.R`).
   `provider_default_model()` just reads that.

2. **Cost tracking.** Costs come from `.PRICES`, a baked-in snapshot of
   [litellm](https://github.com/BerriAI/litellm) prices in `R/sysdata.rda`.
   If the model is in litellm, refresh the snapshot:

   ```sh
   r -e 'source("data-raw/prices.R")'
   ```

   If it isn't (e.g. subscription-only models), add a provider-specific
   price lookup — see `.openai_codex_price_lookup()` in `R/openai-codex.R`.
   With no pricing, `usage$cost` is `NA`; nothing else breaks.

## Adding a provider

Worked example throughout: the `openai_codex` provider. Steps, in order:

1. **Register the name.** Add it to the `provider = c(...)` choices in
   **both** `agent()` and `chat()` (`R/agent.R`). This is the canonical
   list — `provider_default_model()`, corteza, and any other client read
   supported providers from `formals(llm.api::agent)$provider`, so this one
   edit is what makes clients aware of it.

2. **Provider config.** Add a branch to `.get_provider_config()`
   (`R/providers.R`): `base_url`, `chat_path`, `default_model`, and either
   `api_key = .get_key("<provider>")` (key-based) or
   `credentials = <fn>()` (OAuth / custom headers, like codex).

3. **Credentials.**
   - Key-based: add the env var(s) to `.get_key()` (`R/config.R`).
   - OAuth / custom: supply a zero-arg `credentials()` returning the
     request headers (see `openai_codex_credentials()`). Keep real OAuth
     machinery in [tinyoauth](https://github.com/cornball-ai/tinyoauth),
     not here — llm.api should only adapt a token into headers.

4. **Request / response path.** If the provider is OpenAI-chat-compatible,
   the default path in `R/chat.R` / `R/agent.R` already handles it. If it's
   bespoke (different request body, SSE shape, tool-call format), add an
   `R/<provider>.R` with `.chat_<provider>()` and `.agent_<provider>()`
   plus a body builder, response parser, and stream merge — `R/openai-codex.R`
   is the template — and wire the dispatch in `chat()` / `agent()`.

5. **Usage & cost.** Map the provider's usage fields to the standard
   `prompt_tokens` / `completion_tokens` / `total_tokens` shape
   (`.openai_codex_usage()` is the example), and add pricing per the model
   section above.

6. **Convenience wrapper (optional).** `chat_<provider>(prompt, model, ...)`.

7. **Tests.** `inst/tinytest/test_<provider>.R`. Stub the network — see the
   `with_stubbed()` helper in `test_openai_codex.R`. No live API calls.

8. **Docs.** Add the provider to the README Providers list with a usage
   snippet, and to `provider_default_model()`'s `@param`.

### How clients pick it up

Clients should not hardcode provider lists. corteza derives them from
`formals(llm.api::agent)$provider` (`llm_api_supported_providers()` →
`ensure_llm_api_provider()`), so step 1 is usually all it takes for
`corteza::chat(provider = "<new>")` and `corteza --provider <new>` to work.

The exception is anywhere a client runs `match.arg()` against its **own**
list — e.g. corteza's `matrix_configure()` — which has to be updated by
hand. (That was the one spot `openai_codex` needed adding manually.)
