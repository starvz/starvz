% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/phase2_atree.R
\name{panel_utiltreedepth}
\alias{panel_utiltreedepth}
\title{Create the resource utilization by tree depth plot}
\usage{
panel_utiltreedepth(data = NULL, step = 100, legend = TRUE)
}
\arguments{
\item{data}{starvz_data with trace data}

\item{step}{size in milliseconds for the time aggregation step}

\item{legend}{enable/disable plot legends}
}
\value{
A ggplot object
}
\description{
Use starvz_data Application and Atree to create a plot that shows the
total resource utilization, painted by tree depth level using geom_ribbon
}
\examples{
panel_utiltreedepth(data, step=100, legend=TRUE)
}
