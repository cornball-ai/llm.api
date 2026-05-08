# llm.api 0.1.2

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
