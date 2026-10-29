# The plot test/golden/segment_annotate.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/segment_annotate.R > segment_annotate.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# A segment annotated over mtcars' points, ggplot2's annotate() reference example: its ends widen
# neither axis, both lying inside the data's range, and it is in no legend.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x axis
# drawn before the y as in test/golden/point.svg.

library(ggplot2)

plot <- ggplot(mtcars, aes(x = wt, y = mpg)) + geom_point() +
  annotate("segment", x = 2.5, xend = 4, y = 15, yend = 25, colour = "blue") + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
