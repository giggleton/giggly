# The plot test/golden/line_key_big.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/line_key_big.R > line_key_big.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Two crossing lines coloured by group, 8 mm wide: each colour key is widened to the line, 22.68
# points square, as ggplot2's `set_key_size()` reads a path's width.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

data <- data.frame(x = c(1, 2, 1, 2), y = c(1, 2, 2, 1), g = c("a", "a", "b", "b"))
plot <- ggplot(data, aes(x, y, colour = g)) +
  geom_line(linewidth = 8) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
