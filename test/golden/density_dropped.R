# The plot test/golden/density_dropped.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/density_dropped.R > density_dropped.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Two panels: in the first a negative weight makes R's density() fail, so ggplot2 draws nothing
# there; in the second one group's curve and another group of one row, a row of missing values,
# drawn as nothing.

library(ggplot2)
data <- data.frame(
  x = c(1, 2, 3, 5, 8, 1, 2, 4, 6, 9),
  w = c(1, 2, -1, 3, 1, 1, 1, 2, 1, 1),
  g = c("a", "a", "a", "a", "a", "b", "b", "b", "b", "c"),
  p = c("p", "p", "p", "p", "p", "q", "q", "q", "q", "q")
)
plot <- ggplot(data, aes(x, weight = w, group = g)) + geom_density() + facet_wrap(~p) +
  theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
