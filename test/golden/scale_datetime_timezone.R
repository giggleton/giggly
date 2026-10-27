# The plot test/golden/scale_datetime_timezone.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_datetime_timezone.R > scale_datetime_timezone.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A day's load read every hour, 25 readings from 00:00 to 24:00 UTC on 10 March 2024, each the
# reading's index modulo 7 times 1.5 plus a tenth of the index, drawn as points in Kolkata's time,
# five and a half hours ahead: the scale's time zone outranks the column's, so its breaks fall
# every six hours from Kolkata's midnight, at half past the hour in UTC, each labelled by its day
# and time there.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9 (tzdata 2026c): every element and clip path
# matches, the one departure test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

index <- 0:24
df <- data.frame(
  at = as.POSIXct("2024-03-10 00:00:00", tz = "UTC") + index * 60 * 60,
  load = (index %% 7) * 1.5 + index / 10
)
plot <- ggplot(df, aes(at, load)) +
  geom_point() +
  scale_x_datetime(timezone = "Asia/Kolkata") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
