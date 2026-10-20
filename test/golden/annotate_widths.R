# The plot test/golden/annotate_widths.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/annotate_widths.R > annotate_widths.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Points, and a path annotated across them whose width grows along it, 0.5 to 6 mm, drawn a
# segment from each annotation to the next, each as wide as the one it starts from.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

data <- data.frame(x = c(1, 2, 3, 4), y = c(1, 3, 2, 4))
plot <- ggplot(data, aes(x, y)) +
  geom_point() +
  annotate("path", x = c(1, 2, 3, 4), y = c(2, 4, 3, 1), linewidth = c(0.5, 2, 4, 6)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
