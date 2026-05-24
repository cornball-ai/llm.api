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

# ---- Anthropic prompt-cache pricing (multipliers on base input) ----
# claude-sonnet-4-6: input 3e-06, output 1.5e-05. Base 1000/500 = 0.0105.

# 5-minute writes at 1.25x input: +1000*3e-06*1.25 = 0.00375.
expect_equal(llm.api:::.cost_for("claude-sonnet-4-6", "anthropic", 1000, 500,
                                 cache_write_5m = 1000), 0.01425)
# 1-hour writes at 2x input: +1000*3e-06*2 = 0.006.
expect_equal(llm.api:::.cost_for("claude-sonnet-4-6", "anthropic", 1000, 500,
                                 cache_write_1h = 1000), 0.0165)
# Cache reads at 0.1x input: +1000*3e-06*0.1 = 0.0003.
expect_equal(llm.api:::.cost_for("claude-sonnet-4-6", "anthropic", 1000, 500,
                                 cache_read = 1000), 0.0108)
# Four-arg calls are unchanged (cache args default to zero).
expect_equal(llm.api:::.cost_for("claude-sonnet-4-6", "anthropic", 1000, 500),
             0.0105)

# ---- usage_cost(): Anthropic usage shapes ----

# Flat cache_creation total is treated as 5-minute writes.
ant_flat <- list(input_tokens = 1000, output_tokens = 500,
                 cache_creation_input_tokens = 1000,
                 cache_read_input_tokens = 500)
# 0.003 + 0.0075 + 1000*3e-06*1.25 + 500*3e-06*0.1 = 0.0144
expect_equal(llm.api::usage_cost("claude-sonnet-4-6", "anthropic", ant_flat),
             0.0144)

# Per-TTL split prices 5m and 1h writes distinctly.
ant_split <- list(input_tokens = 10, output_tokens = 5,
                  cache_creation = list(ephemeral_5m_input_tokens = 1000,
                                        ephemeral_1h_input_tokens = 2000),
                  cache_read_input_tokens = 0)
# 1e-5*... : 10*3e-06 + 5*1.5e-05 + 1000*3e-06*1.25 + 2000*3e-06*2 = 0.015855
expect_equal(llm.api::usage_cost("claude-sonnet-4-6", "anthropic", ant_split),
             0.015855)

# ---- usage_cost(): OpenAI cached input (data-driven cache_read) ----
# gpt-5.4-mini: input 7.5e-07, output 4.5e-06, cache_read 7.5e-08.
oa <- list(prompt_tokens = 1000, completion_tokens = 500,
           prompt_tokens_details = list(cached_tokens = 400))
# uncached 600*7.5e-07 + 500*4.5e-06 + cached 400*7.5e-08 = 0.00273
expect_equal(llm.api::usage_cost("gpt-5.4-mini", "openai", oa), 0.00273)

# No cached tokens -> plain input pricing.
oa0 <- list(prompt_tokens = 1000, completion_tokens = 500)
expect_equal(llm.api::usage_cost("gpt-5.4-mini", "openai", oa0), 0.003)

# Honest NA: cached tokens present but the model carries no cache_read
# rate in the snapshot -> NA rather than billing reads at full rate.
no_cache <- NULL
for (k in names(llm.api:::.PRICES)) {
    r <- llm.api:::.PRICES[[k]]
    if (identical(r$provider, "openai") && is.null(r$cache_read) &&
        !is.null(r$input) && r$input > 0) {
        no_cache <- k
        break
    }
}
if (!is.null(no_cache)) {
    u_nc <- list(prompt_tokens = 1000, completion_tokens = 100,
                 prompt_tokens_details = list(cached_tokens = 500))
    expect_identical(llm.api::usage_cost(no_cache, "openai", u_nc), NA_real_)
}

# NULL usage -> NA.
expect_identical(llm.api::usage_cost("gpt-5.4-mini", "openai", NULL), NA_real_)

# ---- prices_snapshot_stale() ----
expect_false(llm.api::prices_snapshot_stale(max_age_days = 100000))
expect_true(llm.api::prices_snapshot_stale(max_age_days = -1))

# ---- agent() sums per-turn cost and aggregates cache fields ----
# Stub the Anthropic dispatch with a two-turn run carrying cache tokens.
local({
    ns <- asNamespace("llm.api")
    responses <- list(
        list(text = "",
             assistant_message = list(role = "assistant", content = "t1"),
             tool_calls = list(list(id = "c1", name = "noop", arguments = list())),
             usage = list(input_tokens = 100, output_tokens = 10,
                          cache_creation_input_tokens = 2000,
                          cache_read_input_tokens = 0)),
        list(text = "final",
             assistant_message = list(role = "assistant", content = "final"),
             tool_calls = list(),
             usage = list(input_tokens = 50, output_tokens = 20,
                          cache_read_input_tokens = 2000))
    )
    i <- 0L
    stub <- function(messages, provider_tools, system, model, config, ...) {
        i <<- i + 1L
        responses[[i]]
    }
    orig <- get(".agent_anthropic", envir = ns, inherits = FALSE)
    assignInNamespace(".agent_anthropic", stub, ns = "llm.api")
    res <- tryCatch(
        llm.api::agent(prompt = "go", tools = list(),
                       tool_handler = function(name, args) "ok",
                       provider = "anthropic", model = "claude-sonnet-4-6",
                       verbose = FALSE, max_turns = 5L),
        finally = assignInNamespace(".agent_anthropic", orig, ns = "llm.api"))
    # turn1 0.00795 + turn2 0.00105 = 0.009
    expect_equal(res$usage$cost, 0.009)
    expect_equal(res$usage$input_tokens, 150)
    expect_equal(res$usage$output_tokens, 30)
    expect_equal(res$usage$cache_read_input_tokens, 2000)
    expect_equal(res$usage$cache_creation_input_tokens, 2000)
})
