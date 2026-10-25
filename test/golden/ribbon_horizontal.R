# The plot test/golden/ribbon_horizontal.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/ribbon_horizontal.R > ribbon_horizontal.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A ribbon given xmin and xmax runs up the panel, with no fill and outlined on both edges, over
# an area along y, from 0 across to its x, outlined on its upper edge in no colour, a line
# written with no stroke.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn
# before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
data <- data.frame(y = 1:8, lo = c(1, 2, 1.5, 3, 2.5, 2, 3, 2.5), hi = c(3, 3.5, 4, 5, 4, 4.5, 5, 6))
plot <- ggplot(data) +
  geom_area(aes(x = lo, y = y), orientation = "y", fill = "steelblue", alpha = 0.5) +
  geom_ribbon(aes(y = y, xmin = lo, xmax = hi), colour = "black", fill = NA) +
  theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
