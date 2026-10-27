# The plot test/golden/scale_datetime_zone.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_datetime_zone.R > scale_datetime_zone.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A night's load in New York read every 20 minutes, 31 readings from 21:00 EST on 9 March 2024,
# across the change to daylight saving at 02:00, to 08:00 EDT, each the reading's index modulo 7
# times 1.5 plus a tenth of the index: the x axis takes the column's time zone, its breaks every
# three hours from the local midnight by elapsed time, so the clock's skipped hour moves the
# breaks after it to 04:00 and 07:00, each labelled by its hour and minute in New York.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9 (tzdata 2026c): every element and clip path
# matches, the one departure test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

index <- 0:30
df <- data.frame(
  at = as.POSIXct("2024-03-10 02:00:00", tz = "UTC") + index * 20 * 60,
  load = (index %% 7) * 1.5 + index / 10
)
attr(df$at, "tzone") <- "America/New_York"
plot <- ggplot(df, aes(at, load)) + geom_line() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
