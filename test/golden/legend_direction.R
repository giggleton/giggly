# The plot test/golden/legend_direction.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_direction.R > legend_direction.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size by drive and cylinders, the colour and size legends
# right of the panel with their keys running across, one above the other, as the legends beside
# the panels are stacked whichever way their keys run, each hung from the box's left.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and
# the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv, size = cyl)) +
  geom_point() +
  guides(colour = guide_legend(order = 1), size = guide_legend(order = 2)) +
  theme_gray() +
  theme(legend.direction = "horizontal")

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
