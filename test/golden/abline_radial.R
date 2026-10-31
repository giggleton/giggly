# The plot test/golden/abline_radial.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/abline_radial.R > abline_radial.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Diagonal lines in radial coordinates, which clip nothing, so the extents are not widened: one
# crossing the panel, munched into a curve from where it enters to where it leaves, and one that
# misses it, y = 100 + x above every mpg, drawn as R draws it, a spiral outside the panel and over
# the plot, from x's start, where y is 101, back to x -65, where y meets the radius's end.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, once
# positions are rounded to two decimals (svglite writes one point of the spiral, near the
# drawing's left edge, at x -0.028), and every clip path but svglite's around the whole drawing,
# as in test/golden/radial.R.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg)) + geom_point() +
  geom_abline(intercept = 37, slope = -5, colour = "blue") +
  geom_abline(intercept = 100, slope = 1, colour = "red") +
  coord_radial() +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
