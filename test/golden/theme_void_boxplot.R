# The plot test/golden/theme_void_boxplot.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_void_boxplot.R > theme_void_boxplot.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Two box plots, an outlier each, in theme_void(), their line types mapped so their keys are
# drawn: each box filled with the theme's clear paper and outlined in its ink mixed 20% toward it,
# black at an alpha of CC, as ggplot2 4's GeomBoxplot reads the theme's element_geom(), in the
# plot and in the legend's keys.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, in
# ggplot2's order.

library(ggplot2)

d <- data.frame(g = rep(c("a", "b"), each = 6), y = c(1, 2, 3, 4, 5, 12, 2, 3, 4, 5, 6, 0))
plot <- ggplot(d, aes(g, y, linetype = g)) +
  geom_boxplot() +
  theme_void()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
