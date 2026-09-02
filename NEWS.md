# llm.api 0.1.9.6

* **`cache` now covers the message history, not just the system
  prompt.** `cache = "5m"` / `"1h"` also places a `cache_control`
  marker on the final cacheable block of the final message, so request
  N+1 in an `agent()` loop reads request N's context from cache and
  pays fresh input only for the blocks appended since. With the marker
  on system alone, only the static prefix was ever read back: on one
  agentic run whose history reached ~429k tokens across 239 requests,
  the system marker covered about 0.5% of 59.4M input tokens. Exactly
  one history marker goes out per request however many preceded it
  (the helper strips any already present), the marker is applied to
  the request copy and never to the caller's history, and `"none"` is
  byte-identical to before. `chat()`'s body assembly is split out as
  `.anthropic_chat_body()` so that path is testable without a network
  stub. Not handled: a single request appending more than 20 positions
  of non-tool content, which falls outside Anthropic's lookback and
  rewrites the prefix; documented on the helper.

# llm.api 0.1.9.5

* **`agent()` no longer treats a cut-off response as a clean
  completion** (#38). A truncated response returned through the
  no-tool-calls branch: an interrupted tool call either executed with
  partial arguments or was dropped, so a mid-task cutoff presented as
  a normal finish, possibly with empty content. Every wire's cutoff
  signal is now parsed — Anthropic `stop_reason` `"max_tokens"` and
  `"model_context_window_exceeded"`, chat-completions
  `finish_reason = "length"`, Responses `status = "incomplete"`
  (`max_output_tokens` and `content_filter` alike) — on both the
  streamed and non-streamed transports. On any of them the loop warns
  and returns immediately with `truncated = TRUE` and
  `truncation_reason` (the wire's literal reason), tool calls
  unexecuted, the partial assistant message left out of `history` (as
  on the cancelled path), and `$content` ending in a matching marker:
  `[Output truncated: max_tokens]`,
  `[Output truncated: model_context_window_exceeded]`, or
  `[Response incomplete: <reason>]`.

* `chat()` on the Responses paths (`openai_codex`, and `openai` routed
  through Responses) reported `finish_reason = NULL` even for
  incomplete responses; it now maps to the documented vocabulary:
  `"stop"`, `"length"` for `max_output_tokens`, or the literal reason
  (e.g. `"content_filter"`).

# llm.api 0.1.9.4

* **Every provider streams.** `on_delta` and `llm_cancel()` now work on
  the Chat Completions wire (`openai`, `moonshot`, `ollama`,
  `openai_compatible`) and on the Anthropic Messages wire, not only on
  the Responses providers. Passing `on_delta` no longer warns anywhere,
  because there is nowhere left that ignores it.

* Anthropic content arrives as indexed blocks, and a tool call's
  arguments as `partial_json` fragments that are spliced and parsed only
  once the block closes. Both wires reassemble into exactly the
  non-streamed response shape, so the two paths compare with
  `identical()`.

* **`chat(stream = TRUE)` was broken and is fixed.** It set curl's
  `writefunction` handle option, which curl 7.x rejects outright, so
  every streamed `chat()` threw before reaching the network. Nothing
  caught it: streaming is only used interactively and no test exercised
  it. It also reports `usage` now, where it always returned NULL.

# llm.api 0.1.9.2

* **The model's text, while it is still being written.** `agent()` gains
  `on_delta`, called with each fragment as it arrives on the Responses
  wire (`openai_codex`, and `openai` when `web_search` routes it there).
  Calling `llm_cancel()` from inside it abandons the request: the
  connection closes, the provider stops generating, and `agent()`
  returns `cancelled = TRUE` with the text that had arrived. Every other
  provider posts once and waits, so passing `on_delta` there warns
  rather than doing nothing quietly. Nothing changes for a caller that
  does not pass one.

# llm.api 0.1.9.1

* Images in a user turn. `llm_image()` wraps a file (or raw bytes) and
  `llm_content()` mixes it with text; pass the result as `prompt` to
  `chat()` or `agent()`. Provider-neutral: the same call works against
  Anthropic, the Chat Completions API, and the OpenAI Responses API,
  which spell the block three different ways. `llm_has_image()` is
  there for callers that need to gate on whether the model they are
  pointed at can take one. A plain character prompt is unaffected.

# llm.api 0.1.9

* New `openai_compatible` provider: point `chat()`, `agent()`, and
  `chat_session()` at any OpenAI-compatible gateway (OpenRouter,
  DeepSeek, corporate proxies). The base URL comes from `llm_base()` or
  `OPENAI_COMPATIBLE_BASE_URL` ("/chat/completions" is appended, so
  include any /v1 prefix the gateway expects); the key from
  `llm_key()`, `OPENAI_COMPATIBLE_API_KEY`, or `OPENAI_API_KEY`, and a
  keyless gateway is fine (no Authorization header is sent). Model ids
  pass through untouched and are required (no default). A missing base
  URL or model fails fast with instructions instead of a curl error.
  Requested in cornball-ai/corteza#149.

* `agent()`'s OpenAI-wire request now omits the `Authorization` header
  when no key is configured (matching `chat()`), so keyless gateways
  don't receive a bare "Bearer " header.

* The endpoint/key options are renamed to `llm.api_base` and
  `llm.api_key`, matching the sibling API packages (`tts.api_base`,
  `stt.api_base`, `xtx.api_base`). `llm_base()` / `llm_key()` are
  unchanged. The pre-0.1.8.1 names (`llm.api.api_base` /
  `llm.api.api_key`) are still read as a fallback, with a one-time
  deprecation warning per session.

# llm.api 0.1.8

* Fix: `anthropic_claude` agent runs with tool use no longer error. The agent
  loop now drives the shared Anthropic Messages wire (tool conversion,
  dispatch, and tool-result appending) for the subscription-OAuth provider, so
  the turn after a tool call sends a valid `messages` array instead of 400ing.
  `chat()` was unaffected. Fast-follow on the 0.1.7 cycle.

# llm.api 0.1.7

CRAN release consolidating the 0.1.5–0.1.6.1 development cycle (none of
which were on CRAN). Highlights since the on-CRAN 0.1.4:

* `openai_codex` provider for ChatGPT-subscription-backed Codex, with
  device login / token refresh / caching via tinyoauth (0.1.5).
* `anthropic_claude` provider: drive 'Claude' on a 'Claude' subscription
  via OAuth, no API key. Plus provider-native web search across all four
  hosted providers (0.1.6).
* A read-only per-call context snapshot passed to context-aware
  `tool_handler`s, fully backwards compatible (0.1.6.1).

The per-cycle detail follows.

# llm.api 0.1.6.1

## New features

* `agent()` now passes a read-only per-call **context** snapshot (by name) to a
  `tool_handler` that declares a `context` formal: `assistant_text` (the model's
  text for the turn), `agent_turn`, `call_index`, `call_count`, and `provider`.
  `call_index`/`call_count` count over calls actually dispatched to the handler
  (excluding internally-consumed ones like Moonshot web search). Two-argument
  handlers are called exactly as before, so this is fully backward compatible
  and needs no provider parser changes. Lets a caller surface the model's own
  rationale at tool-approval time or detect tool-call streaks with no narration.

# llm.api 0.1.6

* New `anthropic_claude` provider: drive Claude on a Claude subscription via
  OAuth (no API key), mirroring the `openai_codex` provider. Adds
  `chat_claude_oauth()`, `claude_oauth_login()`, and
  `anthropic_claude_credentials()`, plus `provider = "anthropic_claude"` for
  `chat()`, `agent()`, and `chat_session()`. Login, token caching, and refresh
  run through tinyoauth's Claude route (new in tinyoauth 0.1.1); the Messages
  API request path, prompt caching, thinking, tool use, usage parsing, and cost
  are shared with the API-key `anthropic` provider.

* Provider-native web search: a `web_search` argument on `chat()` and `agent()`
  (FALSE | TRUE | a list of options). When on, the model runs server-side web
  search and the result carries `citations` and `searches`. Wired for all four
  hosted providers:
  - `openai_codex` and `openai` via the OpenAI Responses `web_search` tool. For
    `openai`, the request is routed through the Responses endpoint so search
    works on the default model (the chat-completions path needs a dedicated
    `-search-preview` model).
  - `anthropic` via the Messages `web_search_20250305` tool.
  - `moonshot` via the `$web_search` builtin. Moonshot round-trips the search
    through the tool-call protocol; `llm.api` drives that echo loop internally
    so it stays a single `chat()` / `agent()` call. Moonshot doesn't expose the
    query (so `searches` records that a search ran, with `query = NA`) and
    inlines citations as markdown links in the answer (so `citations` is empty).

  Search is server-side, so it is not gated by `tool_handler`.

# llm.api 0.1.5

* First release of the `openai_codex` provider for ChatGPT-subscription-backed
  Codex (OpenAI Responses API): `chat_openai_codex()`, `agent(provider =
  "openai_codex")`, `openai_codex_credentials()`, and `openai_codex_login()`,
  with device login / token refresh / caching via tinyoauth. Consolidates the
  0.1.4.1-0.1.4.4 development cycle (the per-cycle detail follows).

# llm.api 0.1.4.4

* Fix a 400 from the `openai_codex` provider when `max_tokens` is passed (e.g.
  via `agent()` or `chat()`). The ChatGPT Codex backend rejects both `max_tokens`
  and `max_output_tokens`, so they are now dropped before the request rather than
  forwarded. Since `max_tokens` is a documented argument that Codex can't honor,
  a warning is emitted once per session when a token cap is supplied.

# llm.api 0.1.4.2

* `openai_codex_login()` now returns its credentials callback invisibly (it was
  echoing the whole function body to the console) and prints a confirmation
  with the logged-in account id.

# llm.api 0.1.4.1

* New `openai_codex` provider for ChatGPT subscription-backed OpenAI Codex
  Responses calls: `chat_openai_codex()`, `agent(provider = "openai_codex")`,
  `openai_codex_credentials()`, and `openai_codex_login()`. Device login,
  token refresh, and on-disk caching are handled by
  [tinyoauth](https://github.com/cornball-ai/tinyoauth).

# llm.api 0.1.4

CRAN release consolidating the 0.1.3.1–0.1.3.5 development cycle.
Highlights since the on-CRAN 0.1.3:

* Cache-aware cost estimates. New exported `usage_cost()` prices a
  usage object (Anthropic cache writes/reads via published
  multipliers; 'OpenAI' / 'Moonshot' cache hits from the bundled
  per-model rate), and `chat()` / `agent()` carry it as `usage$cost`.
  New `prices_snapshot_stale()` for staleness alerts. (0.1.3.4)
* Refreshed default models per provider: 'OpenAI' `gpt-5.4-mini`,
  'Anthropic' `claude-sonnet-4-6`, 'Moonshot' `kimi-k2.5`, 'Ollama'
  `qwen3.5:9b`. (0.1.3.5)
* `agent()` gains a `history_callback` for snapshotting intermediate
  state across an interrupt. (0.1.3.1)
* `chat()` / `agent()` gain `cache` (Anthropic prompt caching) and
  `thinking_budget_tokens` (extended thinking); 'OpenAI'
  `max_tokens` is mapped to `max_completion_tokens`. (0.1.3.2)

The per-cycle detail follows.

# llm.api 0.1.3.5

## Refreshed default models

When no model is given, each provider now defaults to a recent,
cost-appropriate, snapshot-priceable model, replacing dated defaults:

* OpenAI: `gpt-5.4-mini` (was `gpt-4o-mini` / `gpt-4o`)
* Anthropic: `claude-sonnet-4-6` everywhere, including `agent()` and
  `chat_session_anthropic()` (which still defaulted to the dated
  `claude-sonnet-4-20250514`)
* Moonshot: `kimi-k2.5` (was `kimi-k2`, which wasn't in the price
  snapshot, so cost estimates came back `NA`)
* Ollama: `qwen3.5:9b` (was `llama3.2`)

This affects `chat()`, `agent()`, and the `chat_*()` / `chat_session_*()`
wrappers. Pass `model =` explicitly to use any other model.

# llm.api 0.1.3.4

## Cache-aware cost estimates

`usage$cost` (from `chat()` and `agent()`) now accounts for prompt
caching instead of billing every input token at the full rate.
Anthropic cache writes/reads are priced from Anthropic's published
multipliers (5-minute write 1.25x, 1-hour write 2x, read 0.1x of the
base input rate), and OpenAI / Moonshot cache hits are priced from
each model's cached-input rate in the bundled snapshot.

New exported helpers:

* `usage_cost(model, provider, usage)` returns the USD estimate for a
  usage object (the same value attached as `usage$cost`), so callers
  can price usage objects directly. Scalar return; cache-aware.
* `prices_snapshot_stale(max_age_days = 90)` reports whether the
  bundled price snapshot is older than a threshold, for staleness
  alerts.

`agent()$usage` now also carries cumulative `cache_read_input_tokens`
and `cache_creation_input_tokens` so callers can inspect cache
activity after a multi-turn run.

The bundled price snapshot was refreshed (2026-05-24) to carry
per-model cached-input rates; base input/output rates for existing
models are unchanged. Cost estimates remain offline and approximate;
`prices_snapshot_date()` docs now spell that out, with source URLs.

# llm.api 0.1.3.3

## Fix: `cache` / `thinking_budget_tokens` silently disabled under the default provider

The Anthropic-only guards in `chat()` ran before provider
auto-detection, comparing against the literal `"auto"` default. So
`chat(prompt, model = "claude-...", cache = "5m")` tripped a spurious
"Anthropic-only" warning, downgraded the opt-in, and fell through to
the default provider. Detection now runs first, so the guards see the
resolved provider. `.validate_thinking_budget()` still runs up front as
provider-independent input validation. Network-free regression coverage
added.

# llm.api 0.1.3.2

Three additions, all backward-compatible (new parameters default to
no-op behaviour) and zero new dependencies.

## Anthropic prompt caching (`cache` parameter)

`chat(cache = c("none", "5m", "1h"))` and
`agent(cache = c("none", "5m", "1h"))`. Default `"none"` preserves
current behaviour; opting in wraps the system message in an
`ephemeral` cache_control block. `"5m"` uses Anthropic's default
TTL; `"1h"` requests the longer cache window. Worth turning on when
the system prompt is long-lived across calls — cache reads cost
~10% of normal input tokens but cache writes cost ~25% more, so
opt-in is the right default. Anthropic-only; warns and degrades to
no-op for other providers.

## Anthropic extended thinking budget (`thinking_budget_tokens`)

`chat(thinking_budget_tokens = N)` and
`agent(thinking_budget_tokens = N)`. When set, sends
`thinking = {type: "enabled", budget_tokens: N}` to the Anthropic
Messages API. Validates inputs early: must be a single integer
>= 1024, and (when `max_tokens` is set) must be strictly less than
it since the budget is counted against `max_tokens`. Anthropic-only;
warns and degrades for other providers.

## OpenAI `max_tokens` → `max_completion_tokens` mapping

OpenAI deprecated `max_tokens` in favour of `max_completion_tokens`,
and o-series reasoning models reject `max_tokens` entirely. `chat()`
and `agent()` now rename for OpenAI requests only; Moonshot and
Ollama (which share the OpenAI-compatible code path) continue to
receive `max_tokens` since their endpoints still expect it. The
rename is gated on the caller not already passing
`max_completion_tokens`, so explicit-set values win.

# llm.api 0.1.3.1

* `agent()` gains a `history_callback` parameter. The callback is
  invoked with the current full history after each assistant message
  is appended and after each tool result is appended. Callers (e.g.
  `corteza`) use it to snapshot intermediate state so an interrupt
  mid-turn doesn't lose tool calls that already completed in this
  batch. Callback errors are swallowed so telemetry can't break a
  turn. Tool results are now appended incrementally to history
  (still as a single batched user message on Anthropic, per the API
  contract); the old `.add_tool_results()` internal helper remains
  for backwards compatibility.

# llm.api 0.1.3

* `chat()` and `agent()` now return `$usage$cost`, a USD scalar
  derived from a bundled snapshot of BerriAI/litellm's
  `model_prices_and_context_window.json` (the same upstream `ellmer`
  uses). Ollama is treated as free (`cost = 0`); models absent from
  the snapshot leave `cost = NA_real_`. A new exported helper
  `prices_snapshot_date()` returns the snapshot date so callers can
  decide when to refresh. Refresh by re-running
  `data-raw/prices.R`.
* New exported helpers `history_tool_calls(history)` and
  `history_count_tool_calls(history, completed_only = FALSE)` for
  walking the message history `agent()` returns. Provider history
  must stay native (it's the input format on the next API call), but
  consumers now get a single canonical record list instead of having
  to know that Anthropic uses `content` blocks (`tool_use` /
  `tool_result`) while OpenAI / moonshot / ollama use a separate
  `tool_calls` field plus `role = "tool"` result messages. Each
  record carries `id`, `name`, `arguments`, `result`, `completed`,
  `call_message_index`, `result_message_index`, and `provider_shape`.
* `agent()` now writes the synthesized tool-call id back into the
  Ollama assistant message when the upstream response omits one.
  Previously `assistant.tool_calls[i].id` and the corresponding
  `role = "tool"` message's `tool_call_id` could disagree, breaking
  history walks that paired calls with results.
* New exported helper `provider_default_model(provider)`. Returns the
  model id `chat()` falls back to when no model is specified, so client
  code can display the resolved model upfront without duplicating the
  lookup table or reaching into internals.
* `chat()` now returns `$thinking` and `$finish_reason`. Reasoning models
  (DeepSeek-R1, Moonshot Kimi, Anthropic extended thinking, OpenRouter)
  put their chain-of-thought in a separate field and previously had it
  silently dropped. `$thinking` is normalized across providers
  (`reasoning_content`, `reasoning`, Anthropic `thinking` blocks).
  `$finish_reason` is normalized to OpenAI vocabulary; Anthropic's
  `max_tokens` becomes `"length"` and `end_turn` becomes `"stop"`.
* `chat()` now warns when a reasoning model truncates mid-thought
  (`finish_reason == "length"` with empty content but populated
  thinking). Previously this returned `content == ""` with no
  indication; the actionable signal is "raise max_tokens".

# llm.api 0.1.1

* Initial CRAN submission.
* Add Moonshot (Kimi) provider alongside OpenAI, Anthropic, and Ollama.
  Detected by base URL or model name; key resolution falls back to
  `OPENAI_API_KEY` since the API is OpenAI-compatible.
* Fix conversation history bug in `agent()` where the final assistant message
  was not appended to the returned history when the agent loop exited
  without further tool calls. Affected all providers but was most visible
  with non-Claude models.
* Drop the `"local"` provider and `chat_local()` / `list_local_models()`
  exports. Direct `llama.cpp` inference via the `localLLM` package is no
  longer supported; use `provider = "ollama"` instead.
