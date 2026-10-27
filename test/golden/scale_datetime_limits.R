# The plot test/golden/scale_datetime_limits.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_datetime_limits.R > scale_datetime_limits.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# test/golden/datetime_line.R's readings on an axis from noon to the last of them, so the line
# through the morning is not drawn, its breaks R's pretty() for eleven hours, every three hours,
# labelled by the time alone.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the one
# departure test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

index <- 0:60
df <- data.frame(
  at = as.POSIXct("2024-03-10 03:00:00", tz = "UTC") + index * 20 * 60,
  load = (index %% 7) * 1.5 + index / 10
)
plot <- ggplot(df, aes(at, load)) +
  geom_line() +
  scale_x_datetime(limits = c(as.POSIXct("2024-03-10 12:00:00", tz = "UTC"), NA)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
