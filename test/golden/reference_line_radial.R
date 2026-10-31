# The plot test/golden/reference_line_radial.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/reference_line_radial.R > reference_line_radial.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Reference lines in radial coordinates: a horizontal line is a circle at its radius, munched
# round the whole turn, and a vertical one a spoke from the centre to the edge at its angle.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, and every
# clip path but svglite's around the whole drawing, as in test/golden/radial.R.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg)) + geom_point() +
  geom_hline(yintercept = 20, colour = "red") +
  geom_vline(xintercept = 3, colour = "blue") +
  coord_radial() +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
