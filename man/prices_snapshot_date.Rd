% tinyrox says don't edit this manually, but it can't stop you!
\name{prices_snapshot_date}
\alias{prices_snapshot_date}
\title{Price snapshot date}
\usage{
prices_snapshot_date()
}
\value{
Character. ISO date string.
}
\description{
Returns the date (`YYYY-MM-DD`) the bundled price table was
snapshotted from BerriAI/litellm. Use this to decide when a
refresh is due.
}
\examples{
\dontrun{
prices_snapshot_date()
}
}
