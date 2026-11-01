# The plot test/golden/summary_ribbon.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/summary_ribbon.R > summary_ribbon.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R does.
#
# A band of the mean's standard error along a continuous x, with the means joined by a line
# over it.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

plot <- ggplot(mtcars, aes(cyl, mpg)) +
  stat_summary(geom = "ribbon", alpha = 0.3) +
  stat_summary(fun = mean, geom = "line") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
