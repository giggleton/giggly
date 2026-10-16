# The plot test/golden/point_colour_legend.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/point_colour_legend.R > point_colour_legend.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage by displacement, every point steelblue, a name R and CSS agree on, and as
# opaque as its number of cylinders, the alpha replacing the colour's own; the legend's keys are
# drawn in the layer's colour at each break's alpha. First checked with ggplot2 4.0.3 and vdiffr
# 1.0.9: every element and clip path matches but svglite's around the whole drawing, and the one
# departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, alpha = cyl)) +
  geom_point(colour = "steelblue") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
