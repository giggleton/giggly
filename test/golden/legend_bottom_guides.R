# The plot test/golden/legend_bottom_guides.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3, and for the gradient svglite and the Liberation fonts, saved as
# giggly-r:ggplot2-4.0.3-svglite. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-svglite \
#     Rscript /golden/legend_bottom_guides.R > legend_bottom_guides.ggplot2.svg
#   docker run --rm -e SVGLITE=1 -v "$PWD/test/golden":/golden:ro \
#     giggly-r:ggplot2-4.0.3-svglite Rscript /golden/legend_bottom_guides.R > legend_bottom_guides.svglite.svg
#
# and compare the first drawing element by element and the gradient's stops against the second,
# as test/golden/point_colourbar.R describes.
#
# guides()'s reference page's legends below the plot: a colour bar for a continuous colour and
# legends for a discrete size and shape, side by side below the x axis's title and above the
# caption, each running across, the colour bar five keys long with its labels below it and its
# title left of it, the legends the legends' spacing apart, each hung from the box's top, the box
# centred across the panel. ggplot2 orders legends by a hash of their titles and labels, and Giggly
# by aesthetic, so `guides(order =)` puts them in Giggly's order.
#
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and svglite 2.2.2: every element and clip path
# matches vdiffr's but the bar's fill, every stop matches svglite's, the gradient runs across the
# bar's middle from its left edge to its right in each drawing, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

dat <- data.frame(x = 1:5, y = 1:5, p = 1:5, q = factor(1:5), r = factor(1:5))
plot <- ggplot(dat, aes(x, y, colour = p, size = q, shape = r)) +
  geom_point() +
  guides(
    colour = guide_colourbar(order = 1, display = "gradient"),
    shape = guide_legend(order = 2),
    size = guide_legend(order = 3)
  ) +
  labs(caption = "Caption") +
  theme_gray() +
  theme(legend.position = "bottom")

file <- tempfile(fileext = ".svg")
if (nzchar(Sys.getenv("SVGLITE"))) {
  svglite::svglite(file, width = 10, height = 8, system_fonts = list(sans = "Liberation Sans"))
  print(plot)
  invisible(dev.off())
} else {
  vdiffr::write_svg(plot, file)
}
cat(readLines(file), sep = "\n")
