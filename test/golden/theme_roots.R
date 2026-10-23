# The plot test/golden/theme_roots.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_roots.R > theme_roots.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Two roots removed, line and rect: every tick, grid line and background goes but what a setting
# gives, which skips the removed root and so has nothing above it to take what it leaves unset
# from, and falls to grid's own defaults: the major y grid lines red, 0.75 points wide with round
# ends; the legend's keys bordered blue 0.75 points wide, on the panel background's fill, which
# legend.key inherits past the removed rect. A colour bar's own white ticks are made as a setting
# is, so they are still drawn, with grid's round ends. vdiffr's device draws no gradient and writes
# the bar's rectangle with no fill, where Giggly's fills it with its gradient: that rectangle's
# `fill` is the one difference in the elements, as test/golden/theme_colorbar.R describes.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but the
# bar's fill, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = cty, shape = drv)) +
  geom_point() +
  facet_wrap(~year) +
  guides(colour = guide_colourbar(display = "gradient")) +
  theme_gray() +
  theme(
    line = element_blank(),
    rect = element_blank(),
    panel.grid.major.y = element_line(colour = "red"),
    legend.key = element_rect(colour = "blue")
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
