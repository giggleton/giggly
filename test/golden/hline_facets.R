# The plot test/golden/hline_facets.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3, and for the gradient svglite and the Liberation fonts, saved as
# giggly-r:ggplot2-4.0.3-svglite. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-svglite \
#     Rscript /golden/hline_facets.R > hline_facets.ggplot2.svg
#   docker run --rm -e SVGLITE=1 -v "$PWD/test/golden":/golden:ro \
#     giggly-r:ggplot2-4.0.3-svglite Rscript /golden/hline_facets.R > hline_facets.svglite.svg
#
# and compare the first drawing element by element and the gradient's stops against the second,
# as test/golden/point_colourbar.R describes.
#
# The reference page's last example: a horizontal line in each panel, mapped from a table of its
# own holding a weight for each number of cylinders, coloured by that weight through the colour
# bar the points share.
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and svglite 2.2.2: every element and clip path
# matches vdiffr's but the bar's fill and the background's edge, written as R's rounding error,
# and every stop matches svglite's.

library(ggplot2)

mean_wt <- data.frame(cyl = c(4, 6, 8), wt = c(2.28, 3.11, 4.00))
plot <- ggplot(mtcars, aes(mpg, wt, colour = wt)) +
  geom_point() +
  geom_hline(aes(yintercept = wt, colour = wt), mean_wt) +
  facet_wrap(~ cyl) +
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
