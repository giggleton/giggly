# The plot test/golden/discrete_band.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/discrete_band.R > discrete_band.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Numbers on a discrete axis: a band from 1.5 to 2.5 across the whole panel, added before mpg's
# bars of each class so it is drawn beneath them, and a label at 4.5, between two classes, added
# after; only the bars map `x`, so the axis is discrete.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

plot <- ggplot(mpg, aes(class)) +
  annotate("rect", xmin = 1.5, xmax = 2.5, ymin = -Inf, ymax = Inf, fill = "blue", alpha = 0.2) +
  geom_bar() +
  annotate("text", x = 4.5, y = 55, label = "between") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
