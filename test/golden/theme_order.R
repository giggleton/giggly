# The plot test/golden/theme_order.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_order.R > theme_order.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size, coloured by fuel, a panel for each drive, with settings
# laid over theme_bw() at a base size of 16 in turn. The red background given before it is dropped
# with the theme it was laid over. The tick labels, removed and then set red, replace theme_bw()'s
# element whole, so they take their size from the text, not 0.8 of it; the grid lines, set red and
# then removed, are gone, and the major ones set 1 millimetre wide after them skip the removal and
# are black, the minor ones still removed. The root text, removed and then set blue, takes what it
# leaves unset from theme_gray()'s at its default size of 11 points, so every text is 11 points or
# its share of that, blue but where its element sets a colour, while the spacing and margins keep
# theme_bw()'s at 16. The points take theme_bw()'s size at 16 and its lines' width, 16/22
# millimetres, as their outline, which no setting changes.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, in
# ggplot2's order, but the background's edge, which R writes as its rounding error.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = fl)) +
  geom_point() +
  facet_wrap(~drv, ncol = 2) +
  labs(title = "Title") +
  theme(plot.background = element_rect(fill = "red")) +
  theme_bw(base_size = 16) +
  theme(axis.text = element_blank(), panel.grid = element_line(colour = "red")) +
  theme(axis.text = element_text(colour = "red"), panel.grid = element_blank()) +
  theme(panel.grid.major = element_line(linewidth = 1)) +
  theme(text = element_blank()) +
  theme(text = element_text(colour = "blue"))

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
