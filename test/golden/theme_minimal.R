# The plot test/golden/theme_minimal.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_minimal.R > theme_minimal.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size, coloured by fuel, a panel for each drive, in
# theme_minimal(): no panel background, border or ticks, the tick labels 4.95 points from the panels
# in their stead, no strip, legend or key background, and the plot's background white with no
# border.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, in
# ggplot2's order.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = fl)) +
  geom_point() +
  facet_wrap(~drv, ncol = 2) +
  labs(title = "Title", subtitle = "Subtitle", caption = "Caption", tag = "A") +
  theme_minimal()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
