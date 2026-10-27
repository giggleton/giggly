# The plot test/golden/scale_datetime_seconds.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_datetime_seconds.R > scale_datetime_seconds.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Fifty-one readings a second apart, from 12:00:00 to 12:00:50 UTC on 10 March 2024, each the
# reading's index modulo 7 times 1.5 plus a tenth of the index, as points: the x axis's breaks
# R's pretty() for under a minute's span, every fifteen seconds, each labelled by its second
# alone.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the one
# departure test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

index <- 0:50
df <- data.frame(
  at = as.POSIXct("2024-03-10 12:00:00", tz = "UTC") + index,
  load = (index %% 7) * 1.5 + index / 10
)
plot <- ggplot(df, aes(at, load)) + geom_point() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
