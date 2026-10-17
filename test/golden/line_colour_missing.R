# The plot test/golden/line_colour_missing.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/line_colour_missing.R > line_colour_missing.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, `<line>`
# elements included.
#
# Three lines grouped by their colour, two in their hues and the one whose colour is missing in
# grey50, its key last and labelled NA, each key a line across it.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

data <- data.frame(
  x = c(1, 2, 3, 1, 2, 3, 1, 2, 3),
  y = c(1, 3, 2, 2, 1, 3, 3, 2, 1),
  g = c("a", "a", "a", "b", "b", "b", NA, NA, NA)
)
plot <- ggplot(data, aes(x, y, colour = g)) + geom_line() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
