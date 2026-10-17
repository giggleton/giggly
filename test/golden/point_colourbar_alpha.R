# The plot test/golden/point_colourbar_alpha.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3, and for the gradient svglite and the Liberation fonts, saved as
# giggly-r:ggplot2-4.0.3-svglite. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-svglite \
#     Rscript /golden/point_colourbar_alpha.R > point_colourbar_alpha.ggplot2.svg
#   docker run --rm -e SVGLITE=1 -v "$PWD/test/golden":/golden:ro \
#     giggly-r:ggplot2-4.0.3-svglite Rscript /golden/point_colourbar_alpha.R > point_colourbar_alpha.svglite.svg
#
# and compare the first drawing element by element, as test/golden/point.R describes. vdiffr's
# device draws no gradient, and writes the colour bar's rectangle with no fill, where Giggly's
# fills it with its gradient: that rectangle's `fill` is the one difference in the elements. The
# gradient is checked against svglite's own drawing, the second: its stops line for line
#
#   diff <(grep "<stop" point_colourbar_alpha.svglite.svg) <(grep "<stop" test/golden/point_colourbar_alpha.svg)
#
# and its ends at the middle of the bar's rectangle, from its bottom to its top, in each drawing.
# svglite measures text with the Liberation font files, vdiffr with its own table of their
# metrics, and its drawing sits a hundredth of a point or so from vdiffr's, so the gradient's ends
# are checked against its own rectangle, not against vdiffr's; its id is svglite's `pat-0`.
#
# mpg's points coloured by their city mileage and as opaque as their cylinders: a legend and a
# colour bar, two kinds of guide, stacked down the right, each left-aligned. ggplot2 orders guides
# by a hash no reader can predict; Giggly orders them by their aesthetics' names, so `guides()` here
# puts alpha first.
#
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and svglite 2.2.2: every element and clip path
# matches vdiffr's but svglite's around the whole drawing and the bar's fill, every stop matches
# svglite's, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = cty, alpha = cyl)) +
  geom_point() +
  guides(
    alpha = guide_legend(order = 1),
    colour = guide_colourbar(order = 2, display = "gradient")
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
if (nzchar(Sys.getenv("SVGLITE"))) {
  svglite::svglite(file, width = 10, height = 8, system_fonts = list(sans = "Liberation Sans"))
  print(plot)
  invisible(dev.off())
} else {
  vdiffr::write_svg(plot, file)
}
cat(readLines(file), sep = "\n")
