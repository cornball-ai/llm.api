% tinyrox says don't edit this manually, but it can't stop you!
\name{chat}
\alias{chat}
\title{Chat with an LLM}
\usage{
chat(prompt, model = NULL, system = NULL, history = NULL, temperature = NULL,
     max_tokens = NULL,
     provider = c("auto", "openai", "anthropic", "moonshot", "ollama", "local"),
     stream = FALSE, ...)
}
\arguments{
\item{prompt}{Character. The user message to send.}

\item{model}{Character. Model name (e.g., "gpt-4o", "claude-3-5-sonnet-latest", "llama3.2").}

\item{system}{Character or NULL. System prompt to set context.}

\item{history}{List or NULL. Previous conversation turns.}

\item{temperature}{Numeric or NULL. Sampling temperature (0-2).}

\item{max_tokens}{Integer or NULL. Maximum tokens in response.}

\item{provider}{Character. Provider: "auto", "openai", "anthropic",
"moonshot", "ollama", or "local".}

\item{stream}{Logical. Stream the response (prints as it arrives).}

\item{...}{Additional parameters passed to the API.}
}
\value{
A list with:
  \item{content}{The assistant's response text}
  \item{model}{Model used}
  \item{usage}{Token usage (if available)}
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
