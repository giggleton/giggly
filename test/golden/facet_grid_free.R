# The plot test/golden/facet_grid_free.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/facet_grid_free.R > facet_grid_free.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Four points in a grid of rows a and b and columns u and v, the pair a and v empty, on free
# scales: each column of panels shares an x scale and each row a y scale, and the axes stay at the
# grid's margins, each column's below it and each row's left of it.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, once
# positions are rounded to two decimals (svglite writes the background's edge as R's rounding
# error), and every clip path matches.

library(ggplot2)

data <- data.frame(
  x = c(1, 2, 3, 10),
  y = c(1, 4, 2, 5),
  r = c("a", "a", "b", "b"),
  c = c("u", "u", "u", "v")
)
plot <- ggplot(data, aes(x, y)) +
  geom_point() +
  facet_grid(r ~ c, scales = "free") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
