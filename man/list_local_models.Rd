% tinyrox says don't edit this manually, but it can't stop you!
\name{list_local_models}
\alias{list_local_models}
\title{List Available Local Models}
\usage{
list_local_models(paths = NULL)
}
\arguments{
\item{paths}{Character vector. Directories to search. Defaults to
common model locations.}
}
\value{
Character vector of found GGUF file paths.
}
\description{
Search for GGUF model files in common locations.
}
\examples{
\dontrun{
list_local_models()
}
}
