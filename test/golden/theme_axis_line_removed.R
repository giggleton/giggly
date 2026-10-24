# The plot test/golden/theme_axis_line_removed.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_axis_line_removed.R > theme_axis_line_removed.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Axis lines set back under a removed line: with nothing above them they are drawn at grid's
# defaults, black, 0.75 points wide with round ends, and the y axis's red and dashed, its dashes
# 4 points, a line that narrow dashed as one of width 1. The x axis has no breaks, so it takes no
# room and draws only its line, as ggplot2's axis exits early.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  scale_x_continuous(breaks = NULL) +
  theme_gray() +
  theme(
    line = element_blank(),
    axis.line = element_line(),
    axis.line.y = element_line(colour = "red", linetype = "dashed")
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
