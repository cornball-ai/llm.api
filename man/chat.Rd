% tinyrox says don't edit this manually, but it can't stop you!
\name{chat}
\alias{chat}
\title{Chat with an LLM}
\usage{
chat(prompt, model = NULL, system = NULL, history = NULL, temperature = NULL,
     max_tokens = NULL,
     provider = c("auto", "openai", "anthropic", "moonshot", "ollama"),
     stream = FALSE, ...)
}
\arguments{
\item{prompt}{Character. The user message to send.}

\item{model}{Character. Model name (e.g., "gpt-4o", "claude-sonnet-4-6", "llama3.2").}

\item{system}{Character or NULL. System prompt to set context.}

\item{history}{List or NULL. Previous conversation turns.}

\item{temperature}{Numeric or NULL. Sampling temperature (0-2).}

\item{max_tokens}{Integer or NULL. Maximum tokens in response.}

\item{provider}{Character. Provider: "auto", "openai", "anthropic",
"moonshot", or "ollama".}

\item{stream}{Logical. Stream the response (prints as it arrives).}

\item{...}{Additional parameters passed to the API.}
}
\value{
A list with:
  \item{content}{The assistant's response text}
  \item{thinking}{Chain-of-thought from reasoning models, or NULL.
    Populated from \code{reasoning_content} (DeepSeek, Moonshot Kimi,
    vLLM, SGLang), \code{reasoning} (OpenRouter), or Anthropic
    \code{thinking} blocks. Normalized across providers.}
  \item{finish_reason}{Why generation stopped. \code{"stop"} on a
    normal completion, \code{"length"} when truncated by max_tokens.
    A reasoning model that returns empty \code{content} with
    \code{finish_reason == "length"} ran out of budget mid-thought;
    raise \code{max_tokens}.}
  \item{model}{Model used}
  \item{usage}{Token usage (if available). When the model is in the
    bundled price snapshot, also carries \code{cost} as a USD scalar;
    Ollama is treated as free (\code{cost = 0}); unknown models leave
    \code{cost = NA_real_}. See \code{\link{prices_snapshot_date}}.}
  \item{history}{Updated conversation history}
}
\description{
Send a message to a Large Language Model and get a response.
}
\examples{
\dontrun{
# Simple chat
chat("What is 2+2?")

# With system prompt
chat("Explain R", system = "You are a helpful programming tutor.")

# Continue conversation
result <- chat("Hello")
chat("Tell me more", history = result$history)
}
}
