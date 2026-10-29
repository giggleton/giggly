# The plot test/golden/rug.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/rug.R > rug.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# The first example on ggplot2's geom_rug reference page: mtcars' points and a rug along the
# bottom and the left, a line 3% of the panel long for each car's weight and mileage.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.svg.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg)) + geom_point() + geom_rug() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
