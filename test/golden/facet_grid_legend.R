# The plot test/golden/facet_grid_legend.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/facet_grid_legend.R > facet_grid_legend.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mtcars' weight against mileage coloured by cylinders, in a row of panels per cylinder count on
# free scales: the strips right of the panels, and the legend beyond them.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, and every
# clip path matches.

library(ggplot2)

plot <- ggplot(mtcars, aes(mpg, wt, colour = factor(cyl))) +
  geom_point() +
  facet_grid(vars(cyl), scales = "free") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
