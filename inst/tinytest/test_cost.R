# Cost lookup against the baked price snapshot. Pure-function,
# offline. The snapshot ships in R/sysdata.rda and is regenerated
# by data-raw/prices.R.

# ---- snapshot is present and dated ----

snap <- llm.api::prices_snapshot_date()
expect_true(is.character(snap) && nzchar(snap),
            info = "prices_snapshot_date() returns a non-empty string")
expect_true(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", snap),
            info = "snapshot date is ISO YYYY-MM-DD")

# ---- Known models (rates from BerriAI/litellm) ----
# 1000 input + 500 output tokens, costs in USD.

# OpenAI gpt-4o: input 2.5e-06, output 1e-05 -> 0.0075
expect_equal(llm.api:::.cost_for("gpt-4o", "openai", 1000, 500), 0.0075)

# Anthropic claude-sonnet-4-6: input 3e-06, output 1.5e-05 -> 0.0105
expect_equal(llm.api:::.cost_for("claude-sonnet-4-6", "anthropic", 1000, 500),
             0.0105)

# Dated Anthropic id resolves to the same per-token rate.
expect_equal(llm.api:::.cost_for("claude-sonnet-4-20250514", "anthropic", 1000, 500),
             0.0105)

# ---- Ollama short-circuits to zero ----

expect_equal(llm.api:::.cost_for("llama3.2", "ollama", 1000, 500), 0)
expect_equal(llm.api:::.cost_for("anything", "ollama", 0, 0), 0)

# ---- Unknown / null model -> NA_real_ ----

expect_identical(llm.api:::.cost_for("totally-not-a-model-xyz", "openai", 1000, 500),
                 NA_real_)
expect_identical(llm.api:::.cost_for(NULL, "openai", 1000, 500), NA_real_)
expect_identical(llm.api:::.cost_for("", "openai", 1000, 500), NA_real_)

# ---- Provider-prefixed fallback ----
# litellm stores some Moonshot models only under "moonshot/<id>". The
# fallback should find them when bare lookup misses.

if (!is.null(llm.api:::.PRICES[["moonshot/kimi-k2.5"]])) {
    expected <- with(llm.api:::.PRICES[["moonshot/kimi-k2.5"]],
                     input * 1000 + output * 500)
    expect_equal(llm.api:::.cost_for("kimi-k2.5", "moonshot", 1000, 500),
                 expected,
                 info = "moonshot prefix fallback hits moonshot/kimi-k2.5")
}

# ---- NA / NULL token counts treated as zero ----

# Known model with no tokens at all -> 0, not NA.
expect_equal(llm.api:::.cost_for("gpt-4o", "openai", 0, 0), 0)
expect_equal(llm.api:::.cost_for("gpt-4o", "openai", NA, NA), 0)
expect_equal(llm.api:::.cost_for("gpt-4o", "openai", NULL, NULL), 0)

# ---- chat() result wiring: .augment_usage_with_cost ----
# Works against both Anthropic-shaped and OpenAI-shaped usage lists.

augment <- llm.api:::.augment_usage_with_cost

anthropic_usage <- list(input_tokens = 1000, output_tokens = 500)
out_a <- augment(anthropic_usage, "claude-sonnet-4-6", "anthropic")
expect_equal(out_a$cost, 0.0105)
expect_equal(out_a$input_tokens, 1000)
expect_equal(out_a$output_tokens, 500)

openai_usage <- list(prompt_tokens = 1000, completion_tokens = 500,
                     total_tokens = 1500)
out_o <- augment(openai_usage, "gpt-4o", "openai")
expect_equal(out_o$cost, 0.0075)
expect_equal(out_o$prompt_tokens, 1000)
expect_equal(out_o$total_tokens, 1500)

# NULL usage passes through (e.g. streaming returns no usage).
expect_null(augment(NULL, "gpt-4o", "openai"))

# Unknown model returns NA_real_ cost but leaves token fields intact.
out_u <- augment(openai_usage, "not-a-real-model", "openai")
expect_identical(out_u$cost, NA_real_)
expect_equal(out_u$prompt_tokens, 1000)
