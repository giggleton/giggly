# The plot test/golden/theme_ontop.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_ontop.R > theme_ontop.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# The panel drawn over the layers: its background, unfilled and bordered grey, and its grid lines
# drawn after the points. The legend's keys unfilled, its background bordered black and dotted,
# the plot's background bordered black and dashed, the dashes on a rectangle as on a line. The x
# axis's ticks of the blank line type draw nothing but keep their room.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, shape = drv)) +
  geom_point() +
  theme_gray() +
  theme(
    panel.ontop = TRUE,
    panel.background = element_rect(fill = NA, colour = "grey50"),
    legend.key = element_rect(fill = NA),
    legend.background = element_rect(colour = "black", linetype = "dotted"),
    plot.background = element_rect(colour = "black", linetype = "dashed", linewidth = 1),
    axis.ticks.x = element_line(linetype = "blank")
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
