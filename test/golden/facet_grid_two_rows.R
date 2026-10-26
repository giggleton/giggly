# The plot test/golden/facet_grid_two_rows.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/facet_grid_two_rows.R > facet_grid_two_rows.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mtcars' weight against mileage in a row of panels for each engine shape and transmission and a
# column for each number of gears: two strips right of each row, the engine shape's outermost, as
# the strips above put the first column on top.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, once
# positions are rounded to two decimals (svglite writes the background's edge as R's rounding
# error), and every clip path matches.

library(ggplot2)

plot <- ggplot(mtcars, aes(mpg, wt)) +
  geom_point() +
  facet_grid(vs + am ~ gear) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
