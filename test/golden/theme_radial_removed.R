# The plot test/golden/theme_radial_removed.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_radial_removed.R > theme_radial_removed.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A radial panel with its axes' ticks removed, the angle axis's labels keeping their place beyond
# where the ticks were, as ggplot2's angle axis keeps their length in its labels' offset; the
# radius axis's labels removed too, so with no ticks it takes no room; and the panel's background,
# a disc, and its minor grid lines removed.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, and every clip path
# but svglite's around the whole drawing, as test/golden/theme_radial.R's.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  coord_radial() +
  theme_gray() +
  theme(
    axis.ticks = element_blank(),
    axis.text.r = element_blank(),
    panel.background = element_blank(),
    panel.grid.minor = element_blank()
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
