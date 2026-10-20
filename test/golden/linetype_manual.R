# The plot test/golden/linetype_manual.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/linetype_manual.R > linetype_manual.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Three series and a fourth whose name is missing, their line types given by name and by pattern:
# dotted, dotdash and 3313; the missing series has none, so it draws no line and its key none.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

data <- data.frame(
  x = rep(c(1, 2, 3), 4),
  y = c(1, 2, 1.5, 2, 3, 2.5, 3, 4, 3.5, 4, 5, 4.5),
  g = rep(c("a", "b", "c", NA), each = 3)
)
plot <- ggplot(data, aes(x, y, linetype = g)) +
  geom_line() +
  scale_linetype_manual(values = c("dotted", "dotdash", "3313")) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
