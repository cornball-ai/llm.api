% tinyrox says don't edit this manually, but it can't stop you!
\name{prices_snapshot_digest}
\alias{prices_snapshot_digest}
\title{Identify the bundled pricing data and calculation}
\usage{
prices_snapshot_digest()
}
\value{
Named list with `table` and `calculation` fingerprints.
}
\description{
Offline MD5 fingerprints identify the serialized price table and the source
of the cost calculation bundled with this build. These are provenance
identifiers, not security checks or a claim that prices are current. The
calculation fingerprint includes provider overrides and cache multipliers.
}
\examples{
prices_snapshot_digest()
}
\seealso{
[prices_snapshot_date()], [usage_cost()]
}
