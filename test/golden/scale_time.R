# The plot test/golden/scale_time.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2, vdiffr and hms, saved as the Docker image giggly-r:ggplot2-4.0.3-hms.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-hms \
#     Rscript /golden/scale_time.R > scale_time.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A day's load read every 20 minutes, 61 readings from 03:20 to 23:20, each the reading's index
# modulo 7 times 1.5 plus a tenth of the index: the x axis a time scale whose breaks are R's
# breaks_hms(), every four hours, found on the extent in hours, the last past midnight written
# 24:00:00 as hms writes it, with minor grid lines midway between them.

library(ggplot2)

index <- 0:60
df <- data.frame(
  at = hms::as_hms(3 * 3600 + 20 * 60 + index * 20 * 60),
  load = (index %% 7) * 1.5 + index / 10
)
plot <- ggplot(df, aes(at, load)) + geom_line() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
