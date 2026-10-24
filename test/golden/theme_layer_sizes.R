# The plot test/golden/theme_layer_sizes.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_layer_sizes.R > theme_layer_sizes.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Two series of points joined by lines and labelled, coloured by series, in theme_gray() at a base
# size of 16 points with lines 1 millimetre wide: each layer's look the theme's where the layer
# leaves it unset, as ggplot2 4's geoms read the theme's element_geom(), the points 16/11 of 1.5
# millimetres with a 1-millimetre outline, the lines 1 millimetre wide and the labels 16 points,
# in the plot and in the legend's keys, which overlay a line, a point and a letter.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, in
# ggplot2's order.

library(ggplot2)

d <- data.frame(x = c(1, 2, 3, 1, 2, 3), y = c(1, 3, 2, 2, 1, 3), g = c("a", "a", "a", "b", "b", "b"))
plot <- ggplot(d, aes(x, y, colour = g)) +
  geom_line() +
  geom_point() +
  geom_text(aes(label = g), nudge_y = 0.2) +
  theme_gray(base_size = 16, base_line_size = 1)

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
