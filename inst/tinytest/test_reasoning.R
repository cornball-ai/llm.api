# Tests for reasoning_content / thinking handling.

# Anthropic stop_reason → finish_reason normalization. Anthropic uses
# different vocabulary than OpenAI; chat() exposes the OpenAI vocabulary
# uniformly, so callers don't have to branch on provider.
expect_null(llm.api:::.normalize_anthropic_stop_reason(NULL))
expect_null(llm.api:::.normalize_anthropic_stop_reason(""))
expect_equal(llm.api:::.normalize_anthropic_stop_reason("end_turn"), "stop")
expect_equal(llm.api:::.normalize_anthropic_stop_reason("max_tokens"), "length")
# Pass-through for values that don't have an OpenAI equivalent.
expect_equal(llm.api:::.normalize_anthropic_stop_reason("tool_use"), "tool_use")
expect_equal(llm.api:::.normalize_anthropic_stop_reason("stop_sequence"),
             "stop_sequence")

# Truncation warning fires only when content is empty AND thinking is
# populated AND finish_reason is "length". This is the silent-failure
# mode of reasoning models that callers need to know about.
expect_warning(
    llm.api:::.warn_if_truncated("", "some reasoning", "length"),
    pattern = "truncated mid-reasoning"
)
# Normal completion with both content and thinking: no warning.
expect_silent(
    llm.api:::.warn_if_truncated("answer", "thinking", "stop")
)
# Length-truncated but content is non-empty: model hit the cap mid-answer
# but at least said something. Caller can decide; we don't warn here.
expect_silent(
    llm.api:::.warn_if_truncated("partial answer", "thinking", "length")
)
# Length-truncated with no thinking and no content: not a reasoning model
# truncation pattern, no warning.
expect_silent(
    llm.api:::.warn_if_truncated("", NULL, "length")
)
# Length-truncated with thinking but content is NULL (some providers).
expect_warning(
    llm.api:::.warn_if_truncated(NULL, "some reasoning", "length"),
    pattern = "truncated mid-reasoning"
)
