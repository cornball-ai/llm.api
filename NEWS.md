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
