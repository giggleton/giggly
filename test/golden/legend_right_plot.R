# The plot test/golden/legend_right_plot.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_right_plot.R > legend_right_plot.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size by drive, in a panel per year under a title and a
# subtitle, its legend right of the panels lined up with the whole plot: centred down every row
# from the strips' top to the x axis's title, not down the panels alone.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but the
# background's left edge, which R writes as its rounding error.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_point() +
  facet_wrap(~year) +
  labs(title = "Title", subtitle = "Subtitle") +
  theme_gray() +
  theme(legend.location = "plot")

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
