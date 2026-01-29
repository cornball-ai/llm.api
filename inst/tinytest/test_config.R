# Test configuration functions

# --- Setup: save and restore options ---
old_opts <- options(llm.api.api_base = NULL, llm.api.api_key = NULL)
on.exit(options(old_opts), add = TRUE)

# --- llm_base() ---

# Returns previous value invisibly
expect_null(llm_base("http://localhost:11434"))

# Sets the option
expect_equal(getOption("llm.api.api_base"), "http://localhost:11434")

# Returns previous value when called again
expect_equal(llm_base("https://api.openai.com"), "http://localhost:11434")
expect_equal(getOption("llm.api.api_base"), "https://api.openai.com")

# --- llm_key() ---

# Reset first
options(llm.api.api_key = NULL)

# Returns previous value (NULL initially)
expect_null(llm_key("sk-test-key"))

# Sets the option
expect_equal(getOption("llm.api.api_key"), "sk-test-key")

# Returns previous value when called again
expect_equal(llm_key("sk-new-key"), "sk-test-key")
