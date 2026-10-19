# The plot test/golden/scale_log10.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_log10.R > scale_log10.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# The scale_continuous reference page's log10 example: mpg's highway mileage on a base-10 log
# axis, too short a span for powers of ten, so marked at 20, 30 and 40, the multiples of ten log
# spacing keeps evenest, with minor grid lines midway between them in log space.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  scale_y_log10() +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
