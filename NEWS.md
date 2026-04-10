# llm.api 0.1.1

* Initial CRAN submission.
* Add Moonshot (Kimi) provider alongside OpenAI, Anthropic, Ollama, and local
  inference. Detected by base URL or model name; key resolution falls back to
  `OPENAI_API_KEY` since the API is OpenAI-compatible.
* Fix conversation history bug in `agent()` where the final assistant message
  was not appended to the returned history when the agent loop exited
  without further tool calls. Affected all providers but was most visible
  with non-Claude models.
