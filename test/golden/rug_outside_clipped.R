# The plot test/golden/rug_outside_clipped.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/rug_outside_clipped.R > rug_outside_clipped.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Rugs outside the panel along every side, six points long, and an annotated one along the
# bottom, in a panel clipped to its edges: every line is drawn, past the edge, and the clip hides
# it.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.svg.

library(ggplot2)

df <- data.frame(x = c(1, 2, 3), y = c(10, 30, 20))
plot <- ggplot(df, aes(x, y)) +
  geom_point() +
  geom_rug(sides = "trbl", outside = TRUE, length = unit(6, "pt")) +
  annotate("rug", x = 2.5, outside = TRUE, colour = "red") +
  coord_cartesian(clip = "on") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
