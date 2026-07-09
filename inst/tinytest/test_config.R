# Test configuration functions

# --- Setup: save and restore options ---
# Clear both the canonical (0.1.8.1+) and legacy option names so a stale
# value from the environment can't leak into these assertions.
old_opts <- options(llm.api_base = NULL, llm.api_key = NULL,
                    llm.api.api_base = NULL, llm.api.api_key = NULL)
old_env <- Sys.getenv(c("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "MOONSHOT_API_KEY"),
                      unset = "")
on.exit(options(old_opts), add = TRUE)
on.exit(do.call(Sys.setenv, as.list(old_env)), add = TRUE)

# --- llm_base() ---

# Returns previous value invisibly
expect_null(llm_base("http://localhost:11434"))

# Sets the canonical option
expect_equal(getOption("llm.api_base"), "http://localhost:11434")

# Returns previous value when called again
expect_equal(llm_base("https://api.openai.com"), "http://localhost:11434")
expect_equal(getOption("llm.api_base"), "https://api.openai.com")

# --- llm_key() ---

# Reset first
options(llm.api_base = NULL, llm.api_key = NULL)

# Returns previous value (NULL initially)
expect_null(llm_key("sk-test-key"))

# Sets the canonical option
expect_equal(getOption("llm.api_key"), "sk-test-key")

# Returns previous value when called again
expect_equal(llm_key("sk-new-key"), "sk-test-key")

# --- .get_key() ---

options(llm.api_key = NULL)
Sys.setenv(MOONSHOT_API_KEY = "moonshot-test-key")
expect_equal(llm.api:::.get_key("moonshot"), "moonshot-test-key")

# --- legacy option names (pre-0.1.8.1) still read, with a deprecation warning ---

# Base: only the legacy name set -> read it, and warn once.
options(llm.api_base = NULL, llm.api.api_base = "https://legacy.example.com")
# Reset the one-time warning latch so this assertion is deterministic
# regardless of test ordering within the session.
rm(list = ls(envir = llm.api:::.deprecated_opt_warned),
   envir = llm.api:::.deprecated_opt_warned)
expect_warning(base_val <- llm.api:::.get_base(), pattern = "deprecated")
expect_equal(base_val, "https://legacy.example.com")

# Canonical name wins over legacy when both are set (no warning).
options(llm.api_base = "https://canonical.example.com")
expect_equal(llm.api:::.get_base(), "https://canonical.example.com")
options(llm.api_base = NULL, llm.api.api_base = NULL)

# Key: legacy name read through .get_key() when no canonical/env key.
options(llm.api_key = NULL, llm.api.api_key = "sk-legacy")
Sys.setenv(OPENAI_API_KEY = "", ANTHROPIC_API_KEY = "", MOONSHOT_API_KEY = "")
rm(list = ls(envir = llm.api:::.deprecated_opt_warned),
   envir = llm.api:::.deprecated_opt_warned)
expect_warning(key_val <- llm.api:::.get_key("openai"), pattern = "deprecated")
expect_equal(key_val, "sk-legacy")
options(llm.api.api_key = NULL)
