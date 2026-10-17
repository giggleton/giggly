# The plot test/golden/point_colour_alpha.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/point_colour_alpha.R > point_colour_alpha.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage by displacement, each point in its class's hue, seven of them round the
# circle as pal_hue() spaces them, and as opaque as its number of cylinders: two legends, stacked
# down the right of the panel, each left-aligned. ggplot2 orders legends by a hash no reader can
# predict; Giggly orders them by their aesthetics' names, so `guides()` here puts alpha first.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = class, alpha = cyl)) +
  geom_point() +
  guides(alpha = guide_legend(order = 1), colour = guide_legend(order = 2)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
