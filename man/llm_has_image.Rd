% tinyrox says don't edit this manually, but it can't stop you!
\name{llm_has_image}
\alias{llm_has_image}
\title{Does this content carry an image?}
\usage{
llm_has_image(x)
}
\arguments{
\item{x}{An \code{llm_content}, an \code{llm_image}, or anything
else (FALSE).}
}
\value{
A single logical.
}
\description{
TRUE when the argument is an \code{\link{llm_content}} holding at
least one \code{\link{llm_image}}, or is an \code{llm_image} itself.
Useful for gating: a caller that may or may not be pointed at a
vision-capable model can ask before sending.
}
\examples{
llm_has_image("just text")
}
