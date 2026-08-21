% tinyrox says don't edit this manually, but it can't stop you!
\name{llm_cancel}
\alias{llm_cancel}
\title{Stop a streaming response early}
\usage{
llm_cancel(message = "cancelled by on_delta")
}
\arguments{
\item{message}{Character. Reason, for the condition object.}
}
\value{
Never returns; raises a condition of class
  \code{llm_cancelled}.
}
\description{
Called from inside an \code{on_delta} callback to abandon the
request. The connection is closed, the provider stops generating,
and \code{\link{agent}} returns what had arrived so far with
\code{cancelled = TRUE}.
}
\details{
This is what makes barge-in possible: a caller speaking the model's
text aloud can stop mid-sentence when the user starts talking, and
stop paying for the rest of a reply nobody is listening to.

Raising it outside a stream is an ordinary error, which is the
honest outcome -- there is nothing to cancel.

}
\examples{
\dontrun{
spoken <- 0
agent("tell me a long story", provider = "openai_codex",
      on_delta = function(text) {
          spoken <<- spoken + nchar(text)
          if (spoken > 200) llm_cancel("heard enough")
      })
}
}
\seealso{
\code{\link{agent}}
}
