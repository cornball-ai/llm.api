% tinyrox says don't edit this manually, but it can't stop you!
\name{llm_content}
\alias{llm_content}
\title{Mixed text and images for one message}
\usage{
llm_content(...)
}
\arguments{
\item{...}{Character scalars and \code{\link{llm_image}} objects.}
}
\value{
An \code{llm_content} object: a list of parts.
}
\description{
Assembles the parts of a single user turn. Character arguments are
text, \code{\link{llm_image}} objects are images, and the order is
the order the model sees them -- which matters: a question asked
before the picture reads differently from one asked after it.
}
\details{
Pass the result as \code{prompt} to \code{\link{chat}} or
\code{\link{agent}}. A plain character prompt is unaffected and
still takes the ordinary path.

}
\examples{
\dontrun{
llm_content("Describe this", llm_image("plot.png"))
}
}
\seealso{
\code{\link{llm_image}}
}
