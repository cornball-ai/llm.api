# MCP (Model Context Protocol) client
#
# Connects to MCP servers via socket transport (base R)

#' Connect to an MCP server
#'
#' Connects to an MCP server via TCP socket.
#'
#' @param host Character. Server hostname (default: "localhost").
#' @param port Integer. Server port.
#' @param name Character. Friendly name for this server.
#' @param timeout Numeric. Connection timeout in seconds (default: 30).
#'
#' @return An MCP connection object (list with socket and tools).
#' @export
#'
#' @examples
#' \dontrun{
#' # Start server first: r mcp_server.R --port 7850
#' conn <- mcp_connect(port = 7850, name = "codeR")
#' tools <- mcp_tools(conn)
#' result <- mcp_call(conn, "read_file", list(path = "README.md"))
#' mcp_close(conn)
#' }
mcp_connect <- function(host = "localhost", port, name = NULL, timeout = 30) {
  # Connect via socket
 sock <- tryCatch(
    socketConnection(
      host = host,
      port = port,
      blocking = TRUE,
      open = "r+b",
      timeout = timeout
    ),
    error = function(e) {
      stop("Failed to connect to MCP server at ", host, ":", port,
           "\n  ", e$message, call. = FALSE)
    }
  )

  conn <- list(
    socket = sock,
    host = host,
    port = port,
    name = name %||% paste0(host, ":", port),
    tools = list(),
    request_id = 0L
  )
  class(conn) <- "mcp_connection"

  # Initialize handshake
  init_result <- .mcp_request(conn, "initialize", list(
    protocolVersion = "2024-11-05",
    capabilities = list(),
    clientInfo = list(name = "llm.api", version = "0.1.0")
  ))

  # Send initialized notification
  .mcp_notify(conn, "notifications/initialized", list())

  # Get tools
  tools_result <- .mcp_request(conn, "tools/list", list())
  conn$tools <- tools_result$tools

  conn
}

#' Start and connect to an MCP server
#'
#' Spawns an MCP server process and connects to it.
#' Requires the server script to support --port argument.
#'
#' @param command Character. Command to run the server (e.g., "r", "Rscript").
#' @param args Character vector. Arguments (path to server script).
#' @param port Integer. Port for the server (default: random 7850-7899).
#' @param name Character. Friendly name.
#' @param startup_wait Numeric. Seconds to wait for server startup.
#'
#' @return An MCP connection object.
#' @export
mcp_start <- function(command, args = character(), port = NULL, name = NULL,
                      startup_wait = 2) {
  # Pick random port if not specified
  if (is.null(port)) {
    port <- sample(7850:7899, 1)
  }

  # Add port argument
  full_args <- c(args, "--port", as.character(port))

  # Start server in background
  if (.Platform$OS.type == "windows") {
    system2(command, full_args, wait = FALSE,
            stdout = FALSE, stderr = FALSE)
  } else {
    system2(command, full_args, wait = FALSE,
            stdout = "/dev/null", stderr = "/dev/null")
  }

  # Wait for server to start
  Sys.sleep(startup_wait)

  # Connect
  mcp_connect(port = port, name = name %||% basename(args[1]))
}

#' List tools from an MCP connection
#'
#' @param conn An MCP connection object.
#' @return List of tool definitions.
#' @export
mcp_tools <- function(conn) {
  conn$tools
}

#' Call a tool on an MCP server
#'
#' @param conn An MCP connection object.
#' @param name Character. Tool name.
#' @param arguments List. Tool arguments.
#'
#' @return Tool result (list with content and text).
#' @export
mcp_call <- function(conn, name, arguments = list()) {
  result <- .mcp_request(conn, "tools/call", list(
    name = name,
    arguments = arguments
  ))

  # Extract text content
  if (!is.null(result$content)) {
    texts <- vapply(result$content, function(c) {
      if (identical(c$type, "text")) c$text else ""
    }, character(1))
    result$text <- paste(texts, collapse = "\n")
  }

  result
}

#' Close an MCP connection
#'
#' @param conn An MCP connection object.
#' @export
mcp_close <- function(conn) {
  tryCatch(close(conn$socket), error = function(e) NULL)
  invisible(NULL)
}

#' Format MCP tools for LLM APIs
#'
#' Converts MCP tool definitions to the format used by Claude/OpenAI.
#'
#' @param conn An MCP connection, or list of connections.
#' @return List of tools in API format.
#' @export
mcp_tools_for_api <- function(conn) {
  if (inherits(conn, "mcp_connection")) {
    conns <- list(conn)
  } else {
    conns <- conn
  }

  tools <- list()
  for (c in conns) {
    for (tool in c$tools) {
      tools[[length(tools) + 1]] <- list(
        name = tool$name,
        description = tool$description %||% "",
        input_schema = tool$inputSchema
      )
    }
  }
  tools
}

#' Format MCP tools for Claude API
#'
#' Alias for mcp_tools_for_api.
#'
#' @param conn An MCP connection, or list of connections.
#' @return List of tools in API format.
#' @export
mcp_tools_for_claude <- mcp_tools_for_api

# Internal: send JSON-RPC request and get response
.mcp_request <- function(conn, method, params) {
  conn$request_id <- conn$request_id + 1L
  id <- conn$request_id

  request <- list(
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params
  )

  json <- jsonlite::toJSON(request, auto_unbox = TRUE, null = "null")

  # Write request
  writeLines(json, conn$socket)

  # Read response
  response_line <- readLines(conn$socket, n = 1, warn = FALSE)

  if (length(response_line) == 0 || nchar(response_line) == 0) {
    stop("MCP server closed connection", call. = FALSE)
  }

  response <- jsonlite::fromJSON(response_line, simplifyVector = FALSE)

  if (!is.null(response$error)) {
    stop("MCP error: ", response$error$message, call. = FALSE)
  }

  response$result
}

# Internal: send notification (no response expected)
.mcp_notify <- function(conn, method, params) {
  request <- list(
    jsonrpc = "2.0",
    method = method,
    params = params
  )

  json <- jsonlite::toJSON(request, auto_unbox = TRUE, null = "null")
  writeLines(json, conn$socket)
  invisible(NULL)
}

#' @export
print.mcp_connection <- function(x, ...) {
  status <- tryCatch({
    if (isOpen(x$socket)) "connected" else "disconnected"
  }, error = function(e) "disconnected")

  cat(sprintf("MCP Connection: %s (%s)\n", x$name, status))
  cat(sprintf("  Endpoint: %s:%d\n", x$host, x$port))
  cat(sprintf("  Tools: %d\n", length(x$tools)))
  if (length(x$tools) > 0) {
    for (tool in x$tools) {
      cat(sprintf("    - %s\n", tool$name))
    }
  }
  invisible(x)
}
