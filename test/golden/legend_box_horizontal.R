# The plot test/golden/legend_box_horizontal.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_box_horizontal.R > legend_box_horizontal.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size by drive and cylinders, the colour and size legends
# side by side right of the panel, the legends' spacing apart, each hung from the box's top, as
# legends beside the panels are justified whatever their arrangement.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and
# the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv, size = cyl)) +
  geom_point() +
  guides(colour = guide_legend(order = 1), size = guide_legend(order = 2)) +
  theme_gray() +
  theme(legend.box = "horizontal")

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
