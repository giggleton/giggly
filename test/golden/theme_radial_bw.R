# The plot test/golden/theme_radial_bw.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_radial_bw.R > theme_radial_bw.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size in radial coordinates, in theme_bw(): the panel's
# background white and its grid light grey, and the border round the panel's square over the points.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in ggplot2's order, and
# every clip path but svglite's around the whole drawing, as test/golden/radial.svg's.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  coord_radial() +
  theme_bw()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
