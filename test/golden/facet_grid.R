# The plot test/golden/facet_grid.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/facet_grid.R > facet_grid.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's city mileage against engine size in a grid, a row of panels per drive train and a column
# per number of cylinders: every drive train crossed with every count, so the three pairs no car
# has are panels drawn empty; the cylinders' strips above the first row, the drive trains' right
# of the last column, turned; axes only below the last row and left of the first column.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, and every
# clip path matches.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, cty)) +
  geom_point() +
  facet_grid(vars(drv), vars(cyl)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
