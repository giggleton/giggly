# The plot test/golden/ribbon_outlines.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/ribbon_outlines.R > ribbon_outlines.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Four ribbons, each with a row missing its ymin, so each draws as two pieces, each polygon
# whole before its outline: outlined on both edges in red over a pink fill at an alpha of 0.5,
# which the outline does not take; on the upper edge alone, 1 mm wide and dashed; on the lower
# edge alone; and bordered whole, where two more rows missing their ymin leave two pieces of one
# row each, a polygon of two points.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn
# before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
base <- data.frame(x = 1:6, lo = c(1, 1.5, 1, NA, 1.2, 1), hi = c(2, 2.5, 2.2, 2.4, 2.6, 2))
shifted <- function(offset, lo = base$lo) data.frame(x = base$x, lo = lo + offset, hi = base$hi + offset)
plot <- ggplot(shifted(0), aes(x, ymin = lo, ymax = hi)) +
  geom_ribbon(outline.type = "both", colour = "red", fill = "pink", alpha = 0.5) +
  geom_ribbon(data = shifted(2), outline.type = "upper", colour = "blue", linewidth = 1,
    linetype = "dashed") +
  geom_ribbon(data = shifted(4), outline.type = "lower", colour = "darkgreen") +
  geom_ribbon(data = shifted(6, c(1, NA, 1, NA, 1.2, 1)), outline.type = "full", colour = "black",
    fill = "orange", linewidth = 0.8) +
  theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
