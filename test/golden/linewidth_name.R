# The plot test/golden/linewidth_name.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/linewidth_name.R > linewidth_name.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# scale_linewidth()'s second example: its first, the legend titled over two lines.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(economics, aes(date, unemploy, linewidth = uempmed)) +
  geom_line(lineend = "round") +
  scale_linewidth("Duration of\nunemployment") +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
