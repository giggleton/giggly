# The plot test/golden/point_no_stroke.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/point_no_stroke.R > point_no_stroke.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, `<line>`
# elements included, reading R's `stroke-width: nan` as Giggly's `0.00`.
#
# test/golden/point_shapes.R's 26 shapes with no stroke, R's NA, Giggly's `:none`, but the last,
# whose stroke is 1: each shape as big as a stroke of 0 makes it, its circles, squares and polygons
# with no outline and its lines not drawn, so shapes 3, 4 and 8 draw nothing, as R's graphics
# engine draws a border of no width transparent and a line of no width not at all. svglite writes
# the width R holds, `nan`, which is not a CSS number; Giggly writes `0.00` beside the same
# `stroke: none`, the one departure. First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every
# element matches, in the same order, the x axis drawn before the y as test/golden/point.R
# describes, and every clip path.

library(ggplot2)

data <- data.frame(x = c(0, 5), y = c(0, 4))
plot <- ggplot(data, aes(x, y)) +
  annotate("point", x = (0:25) %% 6, y = (0:25) %/% 6, shape = 0:25, size = 5,
    stroke = c(rep(NA, 25), 1), colour = "blue", fill = "red", alpha = 0.5) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
