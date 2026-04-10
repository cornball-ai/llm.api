% tinyrox says don't edit this manually, but it can't stop you!
\name{llm_base}
\alias{llm_base}
\title{Set LLM API Base URL}
\usage{
llm_base(url)
}
\arguments{
\item{url}{Character. Base URL for the API endpoint.}
}
\value{
The previous value of the option, invisibly.
}
\description{
Stores a base URL in the \code{llm.api.api_base} option, which
\code{\link{chat}} uses as the default endpoint.
}
\examples{
old <- llm_base("http://localhost:11434")  # 'Ollama'
llm_base(old)  # restore
}
