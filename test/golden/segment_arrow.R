# The plot test/golden/segment_arrow.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/segment_arrow.R > segment_arrow.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Two segments, colour mapped, at an alpha of 0.5, each with closed heads at both ends, 15 degrees
# either side of the line and 0.5 cm long, filled white: each head a polygon written right after its
# line in the line's stroke, its fill at the line's alpha, and each legend key the arrow too, the
# key grown to the head's room, cos(15) x 0.5 cm x 1.25 wide and sin(15) x 0.5 cm x 2 tall. First
# checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x axis drawn
# before the y as in test/golden/point.svg.

library(ggplot2)

df <- data.frame(x = c(1, 2), y = c(1, 3), xend = c(2, 3), yend = c(2, 1), g = c("a", "b"))
plot <- ggplot(df, aes(x, y, xend = xend, yend = yend, colour = g)) +
  geom_segment(
    alpha = 0.5, arrow.fill = "white",
    arrow = arrow(angle = 15, length = unit(0.5, "cm"), ends = "both", type = "closed")
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
