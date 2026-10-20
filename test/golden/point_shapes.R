# The plot test/golden/point_shapes.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/point_shapes.R > point_shapes.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, `<line>`
# elements included.
#
# Each of the 26 shapes R's graphics engine draws a point in, 0 to 25, in rows of six from the
# bottom left, one annotation given a list of shapes, each point 5 mm with a 1 mm stroke, outlined
# blue, filled red, at an alpha of 0.5: the open shapes outlined alone, 15 to 18 filled in the
# colour with no outline, 19 and 20 outlined and filled in the colour, 21 to 25 outlined in the
# colour and filled red, each at half its opacity, and every shape's rectangles, polygons, circles
# and lines in the order R draws them. First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every
# element matches, in the same order, the x axis drawn before the y as test/golden/point.R
# describes, and every clip path.

library(ggplot2)

data <- data.frame(x = c(0, 5), y = c(0, 4))
plot <- ggplot(data, aes(x, y)) +
  annotate("point", x = (0:25) %% 6, y = (0:25) %/% 6, shape = 0:25, size = 5, stroke = 1,
    colour = "blue", fill = "red", alpha = 0.5) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
