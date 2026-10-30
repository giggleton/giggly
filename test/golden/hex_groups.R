# The plot test/golden/hex_groups.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2, vdiffr and hexbin, saved as the Docker image
# giggly-r:ggplot2-4.0.3-hexbin. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-hexbin \
#     Rscript /golden/hex_groups.R > hex_groups.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# A group's hexagons for each drive, 5 across each axis, outlined in the drive's colour and
# unfilled, each group binned on hexagons of its own, the keys a polygon's.
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and hexbin 1.28.6: every element and clip path
# matches, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) + geom_hex(bins = 5, fill = NA) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
