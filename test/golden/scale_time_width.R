# The plot test/golden/scale_time_width.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2, vdiffr and hms, saved as the Docker image giggly-r:ggplot2-4.0.3-hms.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-hms \
#     Rscript /golden/scale_time_width.R > scale_time_width.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A late evening's load read every 5 minutes, 24 readings from 22:00 to 23:55, each the reading's
# index modulo 7 times 1.5 plus a tenth of the index: a break every half hour, laid from the
# multiple of 30 minutes since midnight the widened axis starts in, each labelled by its hour and
# minute, the one at midnight written 00:00 as R's format() wraps it, and a minor grid line every
# ten minutes.

library(ggplot2)

index <- 0:23
df <- data.frame(
  at = hms::as_hms(22 * 3600 + index * 5 * 60),
  load = (index %% 7) * 1.5 + index / 10
)
plot <- ggplot(df, aes(at, load)) +
  geom_line() +
  scale_x_time(date_breaks = "30 mins", date_labels = "%H:%M", date_minor_breaks = "10 mins") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
