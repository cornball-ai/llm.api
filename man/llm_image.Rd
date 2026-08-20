% tinyrox says don't edit this manually, but it can't stop you!
\name{llm_image}
\alias{llm_image}
\title{Image input for a chat message}
\usage{
llm_image(path = NULL, data = NULL, mime = NULL)
}
\arguments{
\item{path}{Path to an image file. Exactly one of \code{path} and
\code{data} is required.}

\item{data}{Raw vector of image bytes, or a character scalar that is
already base64.}

\item{mime}{MIME type such as "image/png". Inferred from
\code{path}'s extension when it is given; required with
\code{data}, which carries no name to infer from.}
}
\value{
An \code{llm_image} object.
}
\description{
Wraps an image so it can be sent to a vision-capable model as part of
a user turn. Combine with text using \code{\link{llm_content}} and
pass the result as \code{prompt} to \code{\link{chat}} or
\code{\link{agent}}.
}
\details{
Provider-neutral: the block is translated into the dialect of
whichever provider the request goes to, so the same call works
against Anthropic, the Chat Completions API, and the OpenAI
Responses API.

The image travels inline, base64-encoded, which is what every one of
these providers accepts without a prior upload. Providers cap how
large that may be (single-digit to low-double-digit megabytes,
depending); resize before calling if the file is big.

}
\examples{
\dontrun{
chat(llm_content("What is in this picture?", llm_image("shot.png")),
     provider = "anthropic")
}
}
\seealso{
\code{\link{llm_content}}
}
