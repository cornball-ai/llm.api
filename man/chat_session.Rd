% tinyrox says don't edit this manually, but it can't stop you!
\name{chat_session}
\alias{chat_session}
\title{Create a stateful chat session}
\usage{
chat_session(model = NULL, system_prompt = NULL,
             provider = c("openai", "anthropic", "moonshot", "ollama"), ...)
}
\arguments{
\item{model}{Character. Model name.}

\item{system_prompt}{Character or NULL. System prompt.}

\item{provider}{Character. Provider: "openai", "anthropic", "moonshot",
or "ollama".}

\item{...}{Additional parameters passed to chat().}
}
\value{
A list with functions:
  \item{chat(message)}{Send a message, returns response text}
  \item{stream(message)}{Stream a response, returns response text}
  \item{stream_async(message)}{Async stream for shinychat (returns string)}
  \item{last_turn()}{Get the last response as list(role, text)}
  \item{history()}{Get full conversation history}
  \item{clear()}{Clear conversation history}
}
\description{
Creates a chat session that maintains conversation history internally.
Returns a list of functions for interacting with the session.
}
\examples{
\dontrun{
# Create a session
session <- chat_session(model = "gpt-4o", system_prompt = "You are helpful.")

# Chat (history maintained automatically)
response <- session$chat("Hello")
response2 <- session$chat("Tell me more")

# Get last response
last <- session$last_turn()
last$text

# Clear and start over
session$clear()
}
}
