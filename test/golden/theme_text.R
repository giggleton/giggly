# The plot test/golden/theme_text.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_text.R > theme_text.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Text and lines set through the theme's tree, on mtcars' fuel economy against weight with a title,
# a caption and a tag: every text 14 points, which the tick labels, red, take one and a half times;
# each axis title, the title, the caption and the tag with margins on more sides than theme_gray()
# gives them; the major grid lines at the y axis's breaks black and the minor ones between the x
# axis's red and twice as wide; and the y axis's ticks 2 mm wide.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg)) +
  geom_point() +
  labs(title = "Fuel economy declines as weight increases", caption = "A caption", tag = "A") +
  theme_gray() +
  theme(
    text = element_text(size = 14),
    axis.text = element_text(colour = "red", size = rel(1.5)),
    axis.title.y = element_text(margin = margin(r = 10, l = 5)),
    axis.title.x = element_text(margin = margin(t = 2, b = 6)),
    plot.title = element_text(size = rel(2), margin = margin(b = 10, l = 20)),
    plot.caption = element_text(margin = margin(t = 4, r = 12)),
    plot.tag = element_text(margin = margin(t = 3, r = 7, b = 5, l = 2)),
    panel.grid.major.y = element_line(colour = "black"),
    panel.grid.minor.x = element_line(colour = "red", linewidth = rel(2)),
    axis.ticks.y = element_line(linewidth = 2)
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
