% tinyrox says don't edit this manually, but it can't stop you!
\name{llm_base}
\alias{llm_base}
\title{Set LLM API Base URL}
\usage{
llm_base(url)
}
\arguments{
\item{url}{Base URL for the API endpoint}
}
\value{
Invisibly returns the previous value
}
\description{
Set LLM API Base URL
}
\examples{
\dontrun{
llm_base("http://localhost:11434")  # Ollama
llm_base("https://api.openai.com")
}
}
