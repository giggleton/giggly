# The plot test/golden/point_fill_stroke.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/point_fill_stroke.R > point_fill_stroke.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_point()'s example of a point's fill and border, on mtcars: shape 21, outlined black and
# filled white, 5 mm with a 5 mm stroke, which draws a 2.5 mm outline and makes the circle bigger.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in the
# same order, the x axis drawn before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg)) +
  geom_point(shape = 21, colour = "black", fill = "white", size = 5, stroke = 5) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
