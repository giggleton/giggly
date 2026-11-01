# The plot test/golden/labels_lines.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/labels_lines.R > labels_lines.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Labels that break over lines: on the x axis, hung from their ticks, each line 0.9 of 1.2 font
# sizes below the one before, the axis as deep as the deepest; on the y axis, centred on their
# breaks; and in a legend, each key's row as tall as its label. First checked with ggplot2 4.0.3
# and vdiffr 1.0.9: every element and clip path matches but svglite's around the whole drawing,
# and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

points <- data.frame(x = c(1, 10, 100, 1000), y = c(1, 2, 3, 4), g = c("a", "b", "c", "d"))

plot <- ggplot(points, aes(x, y, colour = g)) +
  geom_point() +
  scale_x_continuous(
    breaks = c(250, 500, 750),
    labels = c("one", "two\nlines", "three\nof\nthem")
  ) +
  scale_y_continuous(breaks = c(2, 3), labels = c("one", "two\nlines")) +
  scale_colour_discrete(labels = c("one", "two\nlines", "three\nof\nthem", "four")) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
