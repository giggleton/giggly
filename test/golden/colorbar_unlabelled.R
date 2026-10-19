# The plot test/golden/colorbar_unlabelled.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3, and
# for the gradient svglite and the Liberation fonts, saved as giggly-r:ggplot2-4.0.3-svglite. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-svglite \
#     Rscript /golden/colorbar_unlabelled.R > colorbar_unlabelled.ggplot2.svg
#   docker run --rm -e SVGLITE=1 -v "$PWD/test/golden":/golden:ro \
#     giggly-r:ggplot2-4.0.3-svglite Rscript /golden/colorbar_unlabelled.R > colorbar_unlabelled.svglite.svg
#
# and compare the first drawing element by element and the gradient's stops against the second,
# as test/golden/point_colourbar.R describes.
#
# mpg's highway mileage by displacement coloured by city mileage through a palette of three
# colours, the colour bar's labels removed under a title wider than the bar: its ticks still
# drawn, the labels' column and margin left out, the bar left-aligned under the title.
#
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and svglite 2.2.2: every element and clip path
# matches vdiffr's but svglite's around the whole drawing and the bar's fill, every stop matches
# svglite's, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = cty)) +
  geom_point() +
  scale_colour_continuous(
    "a much wider title",
    palette = c("#FEE0D2", "#FC9272", "#DE2D26"),
    labels = NULL
  ) +
  guides(colour = guide_colourbar(display = "gradient")) +
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
