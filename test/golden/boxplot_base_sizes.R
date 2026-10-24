# The plot test/golden/boxplot_base_sizes.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/boxplot_base_sizes.R > boxplot_base_sizes.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Two box plots, an outlier each, in theme_gray() at a base size of 16 points with lines 1
# millimetre wide: each box's lines the theme's borders' width, its median twice it, and its
# outliers 16/11 of 1.5 millimetres, their outline still the 0.5 millimetres geom_boxplot() gives
# them, as ggplot2 4's GeomBoxplot reads the theme's element_geom().
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, in
# ggplot2's order, but the background's edge, which R writes as its rounding error.

library(ggplot2)

d <- data.frame(g = rep(c("a", "b"), each = 6), y = c(1, 2, 3, 4, 5, 12, 2, 3, 4, 5, 6, 0))
plot <- ggplot(d, aes(g, y)) +
  geom_boxplot() +
  theme_gray(base_size = 16, base_line_size = 1)

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
