# The plot test/golden/theme_border_lines.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_border_lines.R > theme_border_lines.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A faceted plot with its panels bordered and its axes drawn as lines. Each panel's border is
# drawn over its points, dashed blue, never filled, inside the clipped panel, so only the inner
# half of its line shows. Each axis a panel draws has its line, red and square-ended, along the
# panel's edge before its ticks, taking no room; the panel above an empty cell draws its bottom
# axis's line where the axis hangs. The ticks are dotted with round ends, and the minor grid
# lines dashed by a pattern of their own, each dash growing with the line's width.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, in
# ggplot2's order.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  facet_wrap(~drv, ncol = 2) +
  theme_gray() +
  theme(
    panel.border = element_rect(colour = "blue", linetype = "dashed"),
    axis.line = element_line(colour = "red", linewidth = 1, lineend = "square"),
    axis.ticks = element_line(linetype = "dotted", lineend = "round", linewidth = 1),
    panel.grid.minor = element_line(linetype = "22")
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
