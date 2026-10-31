# The plot test/golden/abline.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/abline.R > abline.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Diagonal lines given as values over mtcars' points: the reference page's `intercept = 37, slope
# = -5` and `intercept = 20`, its slope 1 by default, and two more each in its own colour and
# width, ended round, one of them flat, in no legend. Each runs between the panel's extents
# widened by their widths, so its ends lie far outside the clipped panel.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg)) + geom_point() +
  geom_abline(intercept = 37, slope = -5) +
  geom_abline(intercept = 20) +
  geom_abline(intercept = c(10, 30), slope = c(2, 0), colour = c("red", "blue"),
    linewidth = c(1, 2), lineend = "round") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
