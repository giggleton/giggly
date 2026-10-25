# The plot test/golden/area_unaligned.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/area_unaligned.R > area_unaligned.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Three groups at different x, the third crossing zero twice, outlined black: each is aligned at
# every x and crossing, the bands above zero piled apart from those below.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn
# before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
data <- data.frame(g = rep(c("a", "b", "c"), each = 3), x = c(1, 3, 5, 2, 4, 6, 1.5, 3.5, 5.5),
  y = c(2, 5, 1, 3, 6, 7, -1, 2, -2))
plot <- ggplot(data, aes(x, y, fill = g)) + geom_area(colour = "black") + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
