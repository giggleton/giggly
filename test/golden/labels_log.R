# The plot test/golden/labels_log.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3, and
# for the gradient svglite and the Liberation fonts, saved as giggly-r:ggplot2-4.0.3-svglite. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-svglite \
#     Rscript /golden/labels_log.R > labels_log.ggplot2.svg
#   docker run --rm -e SVGLITE=1 -v "$PWD/test/golden":/golden:ro \
#     giggly-r:ggplot2-4.0.3-svglite Rscript /golden/labels_log.R > labels_log.svglite.svg
#
# and compare the first drawing element by element and the gradient's stops against the second,
# as test/golden/point_colourbar.R describes.
#
# label_log()'s powers, drawn as plotmath draws a^b: on a log x axis, each base at the label's
# size and its exponent at 0.7 of it, raised, the axis as deep as the highest; on the y axis and
# a colour bar, signed, each sign in the symbol font a thin space before its base, the y axis's
# zero boxed by its own glyph, and the colour bar's missing middle label drawn as nothing, its tick
# kept, as plotmath draws a logical NA. First checked with ggplot2 4.0.3, vdiffr 1.0.9 and svglite
# 2.2.2: every element and clip path matches vdiffr's but svglite's around the whole drawing and
# the bar's fill, every stop matches svglite's, and the one departure is test/golden/point.R's,
# the x axis drawn before the y.

library(ggplot2)

points <- data.frame(x = c(1, 10, 100, 1000), y = c(-100, 0, 50, 100))

plot <- ggplot(points, aes(x, y, colour = y)) +
  geom_point() +
  scale_x_log10(labels = scales::label_log()) +
  scale_y_continuous(breaks = c(-100, 0, 100), labels = scales::label_log()) +
  scale_colour_continuous(
    breaks = c(-100, 0, 100),
    labels = function(breaks) replace(scales::label_log()(breaks), 2, NA)
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
