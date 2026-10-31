# The plot test/golden/discrete_vline.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/discrete_vline.R > discrete_vline.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Numbers on a discrete axis: mpg's highway mileage boxed by class, red lines at 1.5 and 4.5,
# between the classes, and one at 8, past the last, which the axis reaches unwidened.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

plot <- ggplot(mpg, aes(class, hwy)) + geom_boxplot() +
  geom_vline(xintercept = c(1.5, 4.5, 8), colour = "red") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
