# The plot test/golden/scale_datetime_width.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_datetime_width.R > scale_datetime_width.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A working day's load read every 15 minutes, 37 readings from 08:00 to 17:00 UTC on 10 March
# 2024, each the reading's index modulo 7 times 1.5 plus a tenth of the index: a break every two
# hours, laid from the start of the hour the widened axis starts in, each labelled by its hour and
# minute, and a minor grid line every half hour.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the one
# departure test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

index <- 0:36
df <- data.frame(
  at = as.POSIXct("2024-03-10 08:00:00", tz = "UTC") + index * 15 * 60,
  load = (index %% 7) * 1.5 + index / 10
)
plot <- ggplot(df, aes(at, load)) +
  geom_line() +
  scale_x_datetime(date_breaks = "2 hours", date_labels = "%H:%M", date_minor_breaks = "30 mins") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
