# The plot test/golden/legend_inside.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_inside.R > legend_inside.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# theme()'s reference page's legends inside the panel: mtcars' fuel economy against weight, the
# colour legend over the shape legend in a box whose top right corner is placed 95% of the way
# across and up the panel, each legend at the box's right, a 6-point margin inside each.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and
# the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

p2 <- ggplot(mtcars, aes(wt, mpg)) +
  geom_point(aes(colour = factor(cyl), shape = factor(vs))) +
  labs(
    x = "Weight (1000 lbs)",
    y = "Fuel economy (mpg)",
    colour = "Cylinders",
    shape = "Transmission"
  ) +
  guides(colour = guide_legend(order = 1), shape = guide_legend(order = 2))
plot <- p2 +
  theme_gray() +
  theme(
    legend.position = "inside",
    legend.position.inside = c(.95, .95),
    legend.justification = c("right", "top"),
    legend.box.just = "right",
    legend.margin = margin_auto(6)
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
