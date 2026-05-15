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
