# The plot test/golden/legend_justification_top.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_justification_top.R > legend_justification_top.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# theme()'s reference page's legends justified to the top: mtcars' fuel economy against weight,
# the colour legend over the shape legend right of the panel, the box's top at the panel's top.
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
  theme(legend.justification = "top")

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
