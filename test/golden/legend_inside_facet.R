# The plot test/golden/legend_inside_facet.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_inside_facet.R > legend_inside_facet.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size by drive, in a panel per class, seven panels in three
# rows, the legend inside the panels with its bottom right corner at theirs, in the room the
# empty panels leave: the box over all the panels, from the first row's top to the last's bottom,
# the strips above the first row left out.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# the background's left edge, which R writes as its rounding error.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_point() +
  facet_wrap(~class) +
  theme_gray() +
  theme(
    legend.position = "inside",
    legend.position.inside = c(1, 0),
    legend.justification = c(1, 0)
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
