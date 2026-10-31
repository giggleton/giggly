# The plot test/golden/hline_vline.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/hline_vline.R > hline_vline.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Reference lines given as values over mtcars' points: five vertical lines, as the reference
# page's `geom_vline(xintercept = 1:5)`, and two horizontal ones, each its own colour and width,
# their ends round, in no legend.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg)) + geom_point() +
  geom_vline(xintercept = 1:5) +
  geom_hline(yintercept = c(15, 25), colour = c("red", "blue"), linewidth = c(1, 2),
    lineend = "round") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
