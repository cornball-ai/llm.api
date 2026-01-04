# Local llama.cpp backend via localLLM

#' Chat with Local GGUF Model
#'
#' Run inference directly on local GGUF model files using llama.cpp
#' via the localLLM package. No server required.
#'
#' @param prompt Character. The user message to send.
#' @param model Character. Path to GGUF model file, or model name if
#'   models are stored in a standard location.
#' @param system Character or NULL. System prompt to set context.
#' @param n_predict Integer. Maximum tokens to generate. Default 256.
#' @param temperature Numeric. Sampling temperature (0-2). Default 0.7.
#' @param top_p Numeric. Top-p sampling. Default 0.9
#' @param n_gpu_layers Integer. Layers to offload to GPU. Default 0 (CPU only).
#' @param ... Additional parameters passed to localLLM.
#'
#' @return A list with:
#'   \item{content}{The assistant's response text}
#'   \item{model}{Model path used}
#'
#' @export
#' @examples
#' \dontrun
#' # With a local GGUF file
#' chat_local("What is R?", model = "~/models/llama-3.2-1b.gguf")
#'
#' # With GPU acceleration
#' chat_local("Explain Docker", model = "mistral-7b.gguf", n_gpu_layers = 35)
#' }
chat_local <- function(prompt,
                       model,
                       system = NULL,
                       n_predict = 256,
                       temperature = 0.7,
                       top_p = 0.9,
                       n_gpu_layers = 0,
                       ...) {

 if (!requireNamespace("localLLM", quietly = TRUE)) {
    stop(
      "localLLM package required for local inference.\n",
      "Install with: install.packages('localLLM')",
      call. = FALSE
    )
  }

  # Build the full prompt with system context
  full_prompt <- if (!is.null(system)) {
    paste0(
      "<|system|>\n", system, "</s>\n",
      "<|user|>\n", prompt, "</s>\n",
      "<|assistant|>\n"
    )
  } else {
    paste0(
      "<|user|>\n", prompt, "</s>\n",
      "<|assistant|>\n"
    )
  }

  # Generate completion
  result <- localLLM::generate(
    model = model,
    prompt = full_prompt,
    n_predict = n_predict,
    temperature = temperature,
    top_p = top_p,
    n_gpu_layers = n_gpu_layers,
    ...
  )

  # Extract the response text
  content <- if (is.list(result) && !is.null(result$content)) {
    result$content
  } else if (is.character(result)) {
    result
  } else {
    as.character(result)
  }

  list(
    content = content,
    model = model
  )
}

#' List Available Local Models
#'
#' Search for GGUF model files in common locations.
#'
#' @param paths Character vector. Directories to search. Defaults to
#'   common model locations.
#'
#' @return Character vector of found GGUF file paths.
#' @export
#' @examples
#' \dontrun{
#' list_local_models()
#' }
list_local_models <- function(paths = NULL) {
  if (is.null(paths)) {
    paths <- c(
      "~/models",
      "~/.cache/huggingface",
      "~/.ollama/models",
      "/usr/share/models",
      "."
    )
  }

  paths <- path.expand(paths)
  paths <- paths[dir.exists(paths)]

  if (length(paths) == 0) {
    return(character(0))
  }

  models <- unlist(lapply(paths, function(p) {
    list.files(p, pattern = "\\.gguf$", full.names = TRUE, recursive = TRUE)
  }))

  unique(models)
}
