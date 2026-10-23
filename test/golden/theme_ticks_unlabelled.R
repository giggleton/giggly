# The plot test/golden/theme_ticks_unlabelled.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_ticks_unlabelled.R > theme_ticks_unlabelled.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Axes with no labels and ticks of no room: the x axis's scale has no labels and its ticks reach 3
# points into the panel, the y axis's labels are removed and its ticks are 0 points long, so
# neither axis takes any room, and the ticks are drawn from the panel's edge all the same, the y
# axis's as points.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg)) +
  geom_point() +
  scale_x_continuous(labels = NULL) +
  theme_gray() +
  theme(
    axis.ticks.length.x = unit(-3, "pt"),
    axis.ticks.length.y = unit(0, "pt"),
    axis.text.y = element_blank()
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
