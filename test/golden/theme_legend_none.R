# The plot test/golden/theme_legend_none.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_legend_none.R > theme_legend_none.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# legend.position = "none": the colour and size legends are drawn nowhere, and the panel takes
# their room and the spacing before them.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv, size = cyl)) +
  geom_point() +
  theme_gray() +
  theme(legend.position = "none")

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
