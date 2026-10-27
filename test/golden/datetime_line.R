# The plot test/golden/datetime_line.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/datetime_line.R > datetime_line.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A day's load read every 20 minutes, 61 readings from 03:00 to 23:00 UTC on 10 March 2024, each
# the reading's index modulo 7 times 1.5 plus a tenth of the index: the x axis a date-time scale
# whose breaks are R's pretty() for date-times, every six hours from midnight, labelled by day and
# time, with minor grid lines midway between them.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the one
# departure test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

index <- 0:60
df <- data.frame(
  at = as.POSIXct("2024-03-10 03:00:00", tz = "UTC") + index * 20 * 60,
  load = (index %% 7) * 1.5 + index / 10
)
plot <- ggplot(df, aes(at, load)) + geom_line() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
