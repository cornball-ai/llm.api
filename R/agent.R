# Agentic chat with tool use

#' Chat with tool use (agentic mode)
#'
#' Send a prompt to an LLM with tools. Automatically handles tool calls
#' in a loop until the model responds with text only.
#'
#' @param prompt Character. The user message.
#' @param tools List. Tool definitions (from mcp_tools_for_claude or manual).
#' @param tool_handler Function. Called with (name, args), returns result string.
#' @param system Character. System prompt.
#' @param model Character. Model name.
#' @param provider Character. Provider: "anthropic", "openai", "ollama".
#' @param max_turns Integer. Maximum tool-use turns (default: 20).
#' @param verbose Logical. Print tool calls and results.
#' @param ... Additional parameters passed to the API.
#'
#' @return List with final response and conversation history.
#' @export
#'
#' @examples
#' \dontrun{
#' # With MCP server
#' conn <- mcp_connect("r", "mcp_server.R")
#' tools <- mcp_tools_for_claude(conn)
#'
#' result <- agent(
#'   "What files are in the current directory?",
#'   tools = tools,
#'   tool_handler = function(name, args) {
#'     mcp_call(conn, name, args)$text
#'   }
#' )
#' }
agent <- function(
    prompt,
    tools = list(),
    tool_handler = NULL,
    system = NULL,
    model = NULL,
    provider = c("anthropic", "openai", "ollama"),
    max_turns = 20L,
    verbose = TRUE,
    ...
) {
  provider <- match.arg(provider)

  if (is.null(tool_handler) && length(tools) > 0) {
    stop("tool_handler required when tools are provided", call. = FALSE)
  }

  config <- .get_provider_config(provider)

  # Default models with tool support
  if (is.null(model)) {
    model <- switch(provider,
      anthropic = "claude-sonnet-4-20250514",
      openai = "gpt-4o",
      ollama = "llama3.2"
    )
  }

  # Convert tools to provider format
  provider_tools <- .convert_tools(tools, provider)

  # Build initial messages
  messages <- list()
  messages[[1]] <- list(role = "user", content = prompt)

  turn <- 0L

  # Track cumulative token usage
  total_input_tokens <- 0L
  total_output_tokens <- 0L

  while (turn < max_turns) {
    turn <- turn + 1L

    # Make API request with tools
    response <- switch(provider,
      anthropic = .agent_anthropic(messages, provider_tools, system, model, config, ...),
      openai = .agent_openai(messages, provider_tools, system, model, config, ...),
      ollama = .agent_ollama(messages, provider_tools, system, model, config, ...)
    )

    # Accumulate token usage
    if (!is.null(response$usage)) {
      # Anthropic format
      if (!is.null(response$usage$input_tokens)) {
        total_input_tokens <- total_input_tokens + response$usage$input_tokens
        total_output_tokens <- total_output_tokens + response$usage$output_tokens
      }
      # OpenAI/Ollama format
      if (!is.null(response$usage$prompt_tokens)) {
        total_input_tokens <- total_input_tokens + response$usage$prompt_tokens
        total_output_tokens <- total_output_tokens + response$usage$completion_tokens
      }
    }

    # Check if done (no tool calls)
    if (length(response$tool_calls) == 0) {
      return(list(
        content = response$text,
        model = model,
        provider = provider,
        turns = turn,
        history = messages,
        usage = list(
          input_tokens = total_input_tokens,
          output_tokens = total_output_tokens,
          total_tokens = total_input_tokens + total_output_tokens
        )
      ))
    }

    # Add assistant message
    messages[[length(messages) + 1]] <- response$assistant_message

    # Process tool calls
    tool_results <- list()

    for (tc in response$tool_calls) {
      if (verbose) {
        cat(sprintf("\n[Tool: %s]\n", tc$name))
        if (length(tc$arguments) > 0) {
          cat(sprintf("  Args: %s\n",
            jsonlite::toJSON(tc$arguments, auto_unbox = TRUE)))
        }
      }

      # Call tool handler
      result <- tryCatch(
        tool_handler(tc$name, tc$arguments),
        error = function(e) paste("Error:", e$message)
      )

      if (verbose) {
        display <- if (nchar(result) > 500) {
          paste0(substr(result, 1, 500), "...")
        } else {
          result
        }
        cat(sprintf("  Result: %s\n", display))
      }

      tool_results[[length(tool_results) + 1]] <- list(
        id = tc$id,
        name = tc$name,
        result = result
      )
    }

    # Add tool results to messages (format varies by provider)
    messages <- .add_tool_results(messages, tool_results, provider)
  }

  warning("Reached max_turns (", max_turns, ")")
  list(
    content = "[Max turns reached]",
    model = model,
    provider = provider,
    turns = turn,
    history = messages,
    usage = list(
      input_tokens = total_input_tokens,
      output_tokens = total_output_tokens,
      total_tokens = total_input_tokens + total_output_tokens
    )
  )
}

# Convert tools to provider-specific format
.convert_tools <- function(tools, provider) {
  if (length(tools) == 0) return(list())

  switch(provider,
    anthropic = tools,  # Already in Claude format

    openai = lapply(tools, function(t) {
      list(
        type = "function",
        `function` = list(
          name = t$name,
          description = t$description %||% "",
          parameters = t$input_schema
        )
      )
    }),

    ollama = lapply(tools, function(t) {
      list(
        type = "function",
        `function` = list(
          name = t$name,
          description = t$description %||% "",
          parameters = t$input_schema
        )
      )
    })
  )
}

# Anthropic request
.agent_anthropic <- function(messages, tools, system, model, config, ...) {
  url <- paste0(config$base_url, config$chat_path)

  body <- list(
    model = model,
    messages = messages,
    max_tokens = 4096
  )

  if (!is.null(system)) body$system <- system
  if (length(tools) > 0) body$tools <- tools

  extra <- list(...)
  for (name in names(extra)) body[[name]] <- extra[[name]]

  headers <- c(
    "Content-Type" = "application/json",
    "x-api-key" = config$api_key,
    "anthropic-version" = "2023-06-01"
  )

  resp <- .post_json(url, body, headers)

  # Parse response
  text_parts <- character()
  tool_calls <- list()

  for (block in resp$content) {
    if (block$type == "text") {
      text_parts <- c(text_parts, block$text)
    } else if (block$type == "tool_use") {
      tool_calls[[length(tool_calls) + 1]] <- list(
        id = block$id,
        name = block$name,
        arguments = block$input
      )
    }
  }

  list(
    text = paste(text_parts, collapse = "\n"),
    tool_calls = tool_calls,
    assistant_message = list(role = "assistant", content = resp$content),
    usage = resp$usage  # input_tokens, output_tokens
  )
}

# OpenAI request
.agent_openai <- function(messages, tools, system, model, config, ...) {
  url <- paste0(config$base_url, config$chat_path)

  # Build messages with system
  api_messages <- list()
  if (!is.null(system)) {
    api_messages[[1]] <- list(role = "system", content = system)
  }
  api_messages <- c(api_messages, messages)

  body <- list(
    model = model,
    messages = api_messages
  )

  if (length(tools) > 0) body$tools <- tools

  extra <- list(...)
  for (name in names(extra)) body[[name]] <- extra[[name]]

  headers <- c(
    "Content-Type" = "application/json",
    "Authorization" = paste("Bearer", config$api_key)
  )

  resp <- .post_json(url, body, headers)

  # Parse response
  choice <- resp$choices[[1]]
  msg <- choice$message

  tool_calls <- list()
  if (!is.null(msg$tool_calls)) {
    for (tc in msg$tool_calls) {
      args <- tryCatch(
        jsonlite::fromJSON(tc$`function`$arguments, simplifyVector = FALSE),
        error = function(e) list()
      )
      tool_calls[[length(tool_calls) + 1]] <- list(
        id = tc$id,
        name = tc$`function`$name,
        arguments = args
      )
    }
  }

  list(
    text = msg$content %||% "",
    tool_calls = tool_calls,
    assistant_message = msg,
    usage = resp$usage  # prompt_tokens, completion_tokens, total_tokens
  )
}

# Ollama request (OpenAI-compatible)
.agent_ollama <- function(messages, tools, system, model, config, ...) {
  url <- paste0(config$base_url, config$chat_path)

  api_messages <- list()
  if (!is.null(system)) {
    api_messages[[1]] <- list(role = "system", content = system)
  }
  api_messages <- c(api_messages, messages)

  body <- list(
    model = model,
    messages = api_messages,
    stream = FALSE
  )

  if (length(tools) > 0) body$tools <- tools

  extra <- list(...)
  for (name in names(extra)) body[[name]] <- extra[[name]]

  headers <- c("Content-Type" = "application/json")

  resp <- .post_json(url, body, headers)

  # Parse response (OpenAI-compatible format: choices[].message)
  msg <- resp$choices[[1]]$message

  tool_calls <- list()
  if (!is.null(msg$tool_calls)) {
    for (tc in msg$tool_calls) {
      # Parse arguments from JSON string (same as OpenAI)
      args <- tryCatch(
        jsonlite::fromJSON(tc$`function`$arguments, simplifyVector = FALSE),
        error = function(e) list()
      )
      tool_calls[[length(tool_calls) + 1]] <- list(
        id = tc$id %||% paste0("call_", sample(1e9, 1)),
        name = tc$`function`$name,
        arguments = args
      )
    }
  }

  list(
    text = msg$content %||% "",
    tool_calls = tool_calls,
    assistant_message = msg,
    usage = resp$usage
  )
}

# Add tool results to message history
.add_tool_results <- function(messages, results, provider) {
  switch(provider,
    anthropic = {
      # Claude: tool_result blocks in user message
      content <- lapply(results, function(r) {
        list(
          type = "tool_result",
          tool_use_id = r$id,
          content = r$result
        )
      })
      messages[[length(messages) + 1]] <- list(role = "user", content = content)
      messages
    },

    openai = ,
    ollama = {
      # OpenAI/Ollama: separate tool messages
      for (r in results) {
        messages[[length(messages) + 1]] <- list(
          role = "tool",
          tool_call_id = r$id,
          name = r$name,
          content = r$result
        )
      }
      messages
    }
  )
}

# Helper: POST JSON request
.post_json <- function(url, body, headers) {
  h <- curl::new_handle()
  curl::handle_setopt(h,
    customrequest = "POST",
    postfields = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null")
  )
  curl::handle_setheaders(h, .list = as.list(headers))

  resp <- curl::curl_fetch_memory(url, handle = h)

  if (resp$status_code >= 400) {
    err <- tryCatch(
      jsonlite::fromJSON(rawToChar(resp$content)),
      error = function(e) list(error = list(message = rawToChar(resp$content)))
    )
    stop("API error (", resp$status_code, "): ",
      err$error$message %||% "Unknown error", call. = FALSE)
  }

  jsonlite::fromJSON(rawToChar(resp$content), simplifyVector = FALSE)
}


#' Create an agent with MCP servers
#'
#' Convenience function that sets up MCP connections and returns
#' a function for chatting with tools.
#'
#' @param servers Named list of server configs. Each can be:
#'   - `list(port = 7850)` for already-running servers
#'   - `list(command = "r", args = "server.R", port = 7850)` to start and connect
#' @param system Character. Default system prompt.
#' @param model Character. Default model.
#' @param provider Character. Provider: "anthropic", "openai", "ollama".
#' @param verbose Logical. Print tool calls.
#'
#' @return A function that takes a prompt and returns a response.
#' @export
#'
#' @examples
#' \dontrun{
#' # Connect to already-running server
#' chat_fn <- create_agent(
#'   servers = list(codeR = list(port = 7850)),
#'   system = "You are a helpful coding assistant."
#' )
#'
#' # Or start server automatically
#' chat_fn <- create_agent(
#'   servers = list(
#'     codeR = list(command = "r", args = "mcp_server.R", port = 7850)
#'   )
#' )
#'
#' result <- chat_fn("List files in current directory")
#' }
create_agent <- function(
    servers = list(),
    system = NULL,
    model = NULL,
    provider = c("anthropic", "openai", "ollama"),
    verbose = TRUE
) {
  provider <- match.arg(provider)

  # Connect to all servers
  connections <- list()
  for (name in names(servers)) {
    srv <- servers[[name]]

    if (!is.null(srv$command)) {
      # Start server and connect
      connections[[name]] <- mcp_start(
        command = srv$command,
        args = srv$args,
        port = srv$port,
        name = name
      )
    } else {
      # Connect to existing server
      connections[[name]] <- mcp_connect(
        host = srv$host %||% "localhost",
        port = srv$port,
        name = name
      )
    }
  }

  # Gather all tools (in Claude format - will be converted per-provider)
  all_tools <- list()
  tool_map <- list()

  for (name in names(connections)) {
    conn <- connections[[name]]
    for (tool in conn$tools) {
      all_tools[[length(all_tools) + 1]] <- list(
        name = tool$name,
        description = tool$description %||% "",
        input_schema = tool$inputSchema
      )
      tool_map[[tool$name]] <- conn
    }
  }

  # Create tool handler
  handler <- function(name, args) {
    conn <- tool_map[[name]]
    if (is.null(conn)) {
      return(paste("Unknown tool:", name))
    }
    mcp_call(conn, name, args)$text
  }

  # Return chat function
  function(prompt, ...) {
    agent(
      prompt = prompt,
      tools = all_tools,
      tool_handler = handler,
      system = system,
      model = model,
      provider = provider,
      verbose = verbose,
      ...
    )
  }
}
