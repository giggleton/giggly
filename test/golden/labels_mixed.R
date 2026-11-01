# The plot test/golden/labels_mixed.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/labels_mixed.R > labels_mixed.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# An expression vector of labels, as a labels function returning powers among strings makes one:
# every label laid out as plotmath lays it out, a string boxed by its own characters and started
# at its box's start, one of two lines drawn up from its baseline over the ticks, as R draws it;
# the missing label drawn as nothing, its tick kept. First checked with ggplot2 4.0.3 and vdiffr
# 1.0.9: every element and clip path matches but svglite's around the whole drawing, and the one
# departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

points <- data.frame(x = c(1, 10, 100, 1000), y = c(1, 2, 3, 4))

plot <- ggplot(points, aes(x, y)) +
  geom_point() +
  scale_x_log10(
    breaks = c(1, 10, 100, 1000),
    labels = expression("two\nlines", NA, 10^2, "plain")
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
