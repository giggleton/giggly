# The plot test/golden/theme_base_sizes.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_base_sizes.R > theme_base_sizes.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size, coloured by fuel, a panel for each drive, in
# theme_light() at a base size of 16 points, its lines 1 millimetre wide and its borders 2: every
# text 16/11 the size it is at 11 points, every spacing and margin half of 16 points or a share of
# that, the tick length too, the grid, ticks and border their shares of the widths given, and the
# legend's keys still 1.2 lines square. The points take the theme's size, 16/11 of 1.5
# millimetres, and its lines' width as their outline, 1 millimetre, in the panels and the keys.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, in
# ggplot2's order, but the background's edge, which R writes as its rounding error.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = fl)) +
  geom_point() +
  facet_wrap(~drv, ncol = 2) +
  labs(title = "Title") +
  theme_light(base_size = 16, base_line_size = 1, base_rect_size = 2)

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
