# The plot test/golden/legend_top_plot_tag.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_top_plot_tag.R > legend_top_plot_tag.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size by drive, tagged, its legend above the panel lined up
# with the whole plot: centred across every column from the y axis's title to the panel's right,
# the tag's column and the margins left out.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and
# the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_point() +
  labs(tag = "A") +
  theme_gray() +
  theme(legend.position = "top", legend.location = "plot")

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
