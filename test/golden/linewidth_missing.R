# The plot test/golden/linewidth_missing.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/linewidth_missing.R > linewidth_missing.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A line whose width is missing at both ends and once in the middle: the ends are dropped, and the
# segment from the middle row is not drawn, as R's graphics engine draws no line of no width.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

data <- data.frame(x = 1:6, y = c(1, 3, 2, 4, 3, 5), w = c(NA, 1, 2, NA, 3, NA))
plot <- ggplot(data, aes(x, y, linewidth = w)) +
  geom_line() +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
