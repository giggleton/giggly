# The plot test/golden/ribbon_radial.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/ribbon_radial.R > ribbon_radial.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A ribbon outlined black in radial coordinates: each edge is munched on its own into the arc of
# Archimedes' spiral between its points, and the polygon runs out along the upper and back along
# the lower.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, with no
# departure, and every clip path but svglite's around the whole drawing, as in
# test/golden/radial.R.

library(ggplot2)
data <- data.frame(x = 1:6, lo = c(1, 2, 1.5, 3, 2.5, 2), hi = c(3, 3.5, 4, 5, 4, 4.5))
plot <- ggplot(data, aes(x, ymin = lo, ymax = hi)) + geom_ribbon(colour = "black") +
  coord_radial() + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
