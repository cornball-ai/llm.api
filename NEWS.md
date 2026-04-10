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
