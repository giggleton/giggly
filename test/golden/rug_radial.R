# The plot test/golden/rug_radial.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/rug_radial.R > rug_radial.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Rugs in radial coordinates: still straight lines, from the panel's square bottom and left edges,
# each at its point's place on the circle, as ggplot2 draws them.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, and every
# clip path but svglite's around the whole drawing, as in test/golden/radial.R.

library(ggplot2)

df <- data.frame(x = c(1, 2, 3, 4), y = c(1, 3, 2, 4))
plot <- ggplot(df, aes(x, y)) + geom_point() + geom_rug() + coord_radial() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
