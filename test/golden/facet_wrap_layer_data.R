# The plot test/golden/facet_wrap_layer_data.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/facet_wrap_layer_data.R > facet_wrap_layer_data.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# facet_wrap()'s "The same data in every panel" example on test/golden/facet_wrap.R's points:
# a first layer draws the data without its facet column, in light grey, so every panel shows all
# nine points behind its own three, and a text layer's own table holds a cylinder count the data
# lacks, which makes a fourth panel, labelled where the plot's mapping places it. First checked with
# ggplot2 4.0.3 and vdiffr 1.0.9: every element, in order, and every clip path match.

library(ggplot2)

data <- data.frame(
  wt = c(0, 4, 7, 10, 2, 5, 8, 3, 6),
  mpg = c(0, 50, 20, 35, 10, 40, 25, 15, 30),
  cyl = c(4, 4, 4, 6, 6, 6, 8, 8, 8)
)
plot <- ggplot(data, aes(wt, mpg)) +
  geom_point(data = transform(data, cyl = NULL), colour = "#D9D9D9") +
  geom_point() +
  geom_text(aes(label = label), data = data.frame(wt = 5, mpg = 25, cyl = 10, label = "ten")) +
  facet_wrap(vars(cyl)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
