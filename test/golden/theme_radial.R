# The plot test/golden/theme_radial.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_radial.R > theme_radial.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A radial panel's axes set through the theme, on mpg's highway mileage against engine size: the
# angle axis's labels blue with a margin of 8 points above them, its ticks -4 points long, turned
# into the circle, so the labels sit their margin from the circle's edge, the radius axis's ticks
# red and its labels with margins of different widths either side, and the major grid lines at the
# x axis's breaks, round the circle, green, R's #00FF00.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, and every clip path
# but svglite's around the whole drawing, as test/golden/radial.svg's.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  coord_radial() +
  theme_gray() +
  theme(
    axis.text.theta = element_text(colour = "blue", margin = margin(t = 8)),
    axis.ticks.length.theta = unit(-4, "pt"),
    axis.ticks.r = element_line(colour = "red"),
    axis.text.r = element_text(margin = margin(l = 2, r = 6)),
    panel.grid.major.x = element_line(colour = "green")
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
