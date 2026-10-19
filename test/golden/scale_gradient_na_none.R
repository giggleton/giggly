# The plot test/golden/scale_gradient_na_none.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3, and for the gradient svglite and the Liberation fonts, saved as
# giggly-r:ggplot2-4.0.3-svglite. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-svglite \
#     Rscript /golden/scale_gradient_na_none.R > scale_gradient_na_none.ggplot2.svg
#   docker run --rm -e SVGLITE=1 -v "$PWD/test/golden":/golden:ro \
#     giggly-r:ggplot2-4.0.3-svglite Rscript /golden/scale_gradient_na_none.R \
#     > scale_gradient_na_none.svglite.svg
#
# and compare the first drawing element by element and the gradient's stops against the second,
# as test/golden/point_colourbar.R describes.
#
# The scale_gradient reference page's missing-values example in small: six points coloured from
# yellow to red, the two whose z is missing mapped to NA by `na.value = NA` and so not drawn, as
# GeomPoint drops a point whose colour is missing, though the axes span them, x from 1 and y to
# 6, since the scales are trained before; the colour bar spans the four values there are.
#
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and svglite 2.2.2: every element and clip path
# matches vdiffr's but the colour bar's fill, which vdiffr cannot draw, every stop matches
# svglite's, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

data <- data.frame(x = 1:6, y = c(2, 4, 3, 6, 5, 1), z = c(NA, 1, 2, NA, 3, 4))
plot <- ggplot(data, aes(x, y)) +
  geom_point(aes(colour = z)) +
  scale_colour_gradient(low = "yellow", high = "red", na.value = NA) +
  guides(colour = guide_colourbar(display = "gradient")) +
  theme_gray()

file <- tempfile(fileext = ".svg")
if (nzchar(Sys.getenv("SVGLITE"))) {
  svglite::svglite(file, width = 10, height = 8, system_fonts = list(sans = "Liberation Sans"))
  suppressWarnings(print(plot))
  invisible(dev.off())
} else {
  suppressWarnings(vdiffr::write_svg(plot, file))
}
cat(readLines(file), sep = "\n")
