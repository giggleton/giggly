# The plot test/golden/theme_void_legends.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_void_legends.R > theme_void_legends.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size by drive and cylinders under theme_void(), the colour
# legend over the size legend: theme_void() sets no space between legends, and ggplot2's guide box
# then puts half a line between them, 7.2 points.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv, size = cyl)) +
  geom_point() +
  guides(colour = guide_legend(order = 1), size = guide_legend(order = 2)) +
  theme_void()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
