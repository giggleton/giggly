# The plot test/golden/theme_colorbar.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_colorbar.R > theme_colorbar.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A colour bar set through the theme, on mpg's points coloured by city mileage as
# test/golden/point_colourbar.svg draws them: ticks black, so as wide as the theme's lines, the bar
# 0.8 cm wide and five half-inch keys long, each tick reaching half a key into it, and the labels'
# margins either side of them. vdiffr's device draws no gradient and writes the bar's rectangle
# with no fill, where Giggly's fills it with its gradient: that rectangle's `fill` is the one
# difference in the elements. The gradient's stops are test/golden/point_colourbar.svg's, which
# test/golden/point_colourbar.R checks against svglite's, and its ends run up the middle of the
# bar's rectangle, from its bottom to its top.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing and the bar's fill, and the one departure is
# test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = cty)) +
  geom_point() +
  guides(colour = guide_colourbar(display = "gradient")) +
  theme_gray() +
  theme(
    legend.ticks = element_line(colour = "black"),
    legend.key.width = unit(0.8, "cm"),
    legend.key.height = unit(0.5, "in"),
    legend.ticks.length = rel(0.5),
    legend.text = element_text(margin = margin(l = 2, r = 9))
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
