# The plot test/golden/theme_void_bars.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_void_bars.R > theme_void_bars.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Bars outlined by group and an annotated rectangle in theme_void(), whose paper is its ink with no
# alpha: each bar's and the rectangle's fill the theme's ink mixed 35% toward that paper, black at
# an alpha of A6, as ggplot2 4's GeomRect mixes it from the theme's element_geom(), in the plot and
# in the legend's keys.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, in
# ggplot2's order.

library(ggplot2)

d <- data.frame(x = c(1, 2, 3), y = c(3, 1, 2), g = c("a", "b", "a"))
plot <- ggplot(d, aes(x, y, colour = g)) +
  geom_col() +
  annotate("rect", xmin = 2.6, xmax = 3.4, ymin = 2.5, ymax = 3) +
  theme_void()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
