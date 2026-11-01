# The plot test/golden/errorbar_spaced.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/errorbar_spaced.R > errorbar_spaced.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R does.
#
# Dotted error bars ended square on a continuous axis, whiskers 0.9 of its closest spacing, and
# an annotated error bar and crossbar between them.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

spaced <- data.frame(x = c(1, 2, 4), y = c(2, 3, 1), lo = c(1, 2.5, 0), hi = c(3, 4, 1.5),
  g = c("a", "b", "a"))

plot <- ggplot(spaced, aes(x, y, ymin = lo, ymax = hi)) +
  geom_errorbar(lineend = "square", linewidth = 1, linetype = "dotted") +
  annotate("errorbar", x = 3, ymin = 1, ymax = 2, width = 0.5, colour = "red") +
  annotate("crossbar", x = 3, y = 3, ymin = 2.5, ymax = 3.5, colour = "blue") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
