# The plot test/golden/shape_missing.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/shape_missing.R > shape_missing.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Five points, one with no value: it is unshaped, so not drawn, and the legend's last key, labelled
# NA, draws no glyph.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

data <- data.frame(x = 1:5, y = 1:5, g = c("a", "b", NA, "c", "a"))
plot <- ggplot(data, aes(x, y, shape = g)) + geom_point() + theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
