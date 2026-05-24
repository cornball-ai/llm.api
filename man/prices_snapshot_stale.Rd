% tinyrox says don't edit this manually, but it can't stop you!
\name{prices_snapshot_stale}
\alias{prices_snapshot_stale}
\title{Is the bundled price snapshot stale?}
\usage{
prices_snapshot_stale(max_age_days = 90)
}
\arguments{
\item{max_age_days}{Numeric. Age threshold in days; default 90.}
}
\value{
`TRUE` when the bundled snapshot is older than
  `max_age_days`, otherwise `FALSE`.
}
\description{
Convenience wrapper over [prices_snapshot_date()] for staleness
alerts, so callers don't repeat the date arithmetic. Offline only;
it does not check the network for newer prices.
}
\examples{
prices_snapshot_stale()
prices_snapshot_stale(max_age_days = 30)
}
\seealso{
[prices_snapshot_date()]
}
