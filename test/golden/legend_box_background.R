# The plot test/golden/legend_box_background.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_box_background.R > legend_box_background.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# theme()'s reference page's box around the legends: mtcars' fuel economy against weight, the
# colour legend over the shape legend right of the panel, in a box with a 6-point margin and a
# background. ggplot2's guide box draws `legend.box.background` as the theme holds it, never
# through `calc_element()`, so `element_rect()` takes nothing from `rect`: a white fill and a black
# border 0.75 points wide, grid's own, where `rect` would give 1.07.
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
  theme(legend.box.background = element_rect(), legend.box.margin = margin_auto(6))

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
