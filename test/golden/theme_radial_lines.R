# The plot test/golden/theme_radial_lines.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_radial_lines.R > theme_radial_lines.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A radial panel with its axes drawn as lines, its border and the panel on top. The radius axis's
# line runs up the panel's left edge from the circle's centre to its top, 30 points munched as a
# spoke is; the angle axis's, red and a millimetre wide, round the circle's edge, 186 points
# munched as a grid circle is, after the angle axis's ticks. The panel's background, an unfilled
# disc bordered dotted green, and its dashed major grid lines are drawn over the points, under the
# angle axis and the border, a rectangle round the whole panel, which is not clipped.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in ggplot2's order,
# and every clip path but svglite's around the whole drawing, as test/golden/theme_radial.R's.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  coord_radial() +
  theme_gray() +
  theme(
    axis.line = element_line(colour = "red"),
    axis.line.theta = element_line(linewidth = 1),
    panel.border = element_rect(colour = "blue"),
    panel.grid.major = element_line(linetype = "dashed"),
    panel.background = element_rect(fill = NA, colour = "darkgreen", linetype = "dotted"),
    panel.ontop = TRUE
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
