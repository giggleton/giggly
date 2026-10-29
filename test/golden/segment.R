# The plot test/golden/segment.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/segment.R > segment.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Four segments, colour and line type mapped to one variable, drawn with round ends: each row a
# straight line in its own colour and line type, in row order, and the legend's keys a path's.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x axis
# drawn before the y as in test/golden/point.svg.

library(ggplot2)

df <- data.frame(
  x = c(1, 2, 3, 4), y = c(1, 3, 2, 4),
  xend = c(2, 3, 4, 5), yend = c(2, 1, 4, 3),
  g = c("a", "b", "a", "b")
)
plot <- ggplot(df, aes(x, y, xend = xend, yend = yend, colour = g, linetype = g)) +
  geom_segment(linewidth = 1, lineend = "round") + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
