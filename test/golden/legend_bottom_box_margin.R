# The plot test/golden/legend_bottom_box_margin.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_bottom_box_margin.R > legend_bottom_box_margin.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size by drive and cylinders below the panel: the colour
# legend with no title, its keys starting at the legend's margin, beside the size legend, whose
# points from 2 to 10 millimetres make some keys taller than the theme's and their row as tall as
# the tallest, in a box with a margin of a different width on each side and a background over it.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and
# the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv, size = cyl)) +
  geom_point() +
  scale_size(range = c(2, 10)) +
  labs(colour = NULL) +
  guides(colour = guide_legend(order = 1), size = guide_legend(order = 2)) +
  theme_gray() +
  theme(
    legend.position = "bottom",
    legend.box.margin = margin(4, 8, 12, 16),
    legend.box.background = element_rect()
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
