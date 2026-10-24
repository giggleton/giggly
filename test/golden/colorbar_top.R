# The plot test/golden/colorbar_top.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3, and for the gradient svglite and the Liberation fonts, saved as
# giggly-r:ggplot2-4.0.3-svglite. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-svglite \
#     Rscript /golden/colorbar_top.R > colorbar_top.ggplot2.svg
#   docker run --rm -e SVGLITE=1 -v "$PWD/test/golden":/golden:ro \
#     giggly-r:ggplot2-4.0.3-svglite Rscript /golden/colorbar_top.R > colorbar_top.svglite.svg
#
# and compare the first drawing element by element and the gradient's stops against the second,
# as test/golden/point_colourbar.R describes.
#
# mpg's highway mileage against engine size coloured by itself, the colour bar above the panel,
# running across, five keys long and one tall, its ticks across its bottom and then its top, its
# labels below it, centred on their ticks, and its title left of it, centred down the bar and its
# labels.
#
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and svglite 2.2.2: every element and clip path
# matches vdiffr's but the bar's fill, every stop matches svglite's, the gradient runs across the
# bar's middle from its left edge to its right in each drawing, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = hwy)) +
  geom_point() +
  guides(colour = guide_colourbar(display = "gradient")) +
  theme_gray() +
  theme(legend.position = "top")

file <- tempfile(fileext = ".svg")
if (nzchar(Sys.getenv("SVGLITE"))) {
  svglite::svglite(file, width = 10, height = 8, system_fonts = list(sans = "Liberation Sans"))
  print(plot)
  invisible(dev.off())
} else {
  vdiffr::write_svg(plot, file)
}
cat(readLines(file), sep = "\n")
