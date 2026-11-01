# The plot test/golden/labels_legend.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/labels_legend.R > labels_legend.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A string and a missing label among signed powers on a size legend, each key's label drawn alone
# from its element of the expression vector, as ggplot2 draws a legend's: the powers as plotmath
# draws them, the string as text, and the missing one NA, as text. First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path
# matches but svglite's around the whole drawing, and the one departure is test/golden/point.R's,
# the x axis drawn before the y.

library(ggplot2)

points <- data.frame(x = c(1, 2, 3, 4), y = c(-100, 0, 50, 100))

plot <- ggplot(points, aes(x, y, size = y)) +
  geom_point() +
  scale_size_continuous(
    breaks = c(-100, 0, 50, 100),
    labels = expression(-10^2, "x", NA, +10^2)
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
