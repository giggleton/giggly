# The plot test/golden/theme_margins.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_margins.R > theme_margins.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.

#
# Margins on the sides only a theme setting gives, on mtcars' fuel economy against weight coloured
# by cylinders, with a title, a subtitle and a caption: the x axis's labels with margins above and
# below them, the title with margins above and below it, the caption with margins above and below
# it, and a legend with no labels, its labels 30 points, so they would be taller than the keys,
# and its title 40 points of margin to its right, which makes it the legend's widest part and
# replaces the gap below it.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) +
  geom_point() +
  labs(title = "Fuel economy", subtitle = "By weight", caption = "A caption") +
  scale_colour_discrete(labels = NULL) +
  theme_gray() +
  theme(
    axis.text.x = element_text(margin = margin(t = 2, b = 3)),
    plot.title = element_text(margin = margin(t = 6, b = 4)),
    plot.caption = element_text(margin = margin(t = 2, b = 5)),
    legend.title = element_text(margin = margin(r = 40)),
    legend.text = element_text(size = 30)
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
