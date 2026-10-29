# The plot test/golden/segment_ends.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/segment_ends.R > segment_ends.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Segments given one end: a layer mapping only xend ends each at its own y, and one mapping only
# yend at its own x. A row missing x or xend draws nothing, and an infinite xend reaches the
# panel's edge.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x axis
# drawn before the y as in test/golden/point.svg.

library(ggplot2)

df <- data.frame(x = c(1, 2, NA, 4), y = c(1, 2, 3, 4), x2 = c(2, NA, 4, Inf), y2 = c(0, 1, 2, 3))
plot <- ggplot(df, aes(x, y)) +
  geom_segment(aes(xend = x2), colour = "steelblue", linewidth = 2) +
  geom_segment(aes(yend = y2), linetype = "dashed") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
