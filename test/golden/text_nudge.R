# The plot test/golden/text_nudge.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/text_nudge.R > text_nudge.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# position_nudge()'s "Or, in brief" example from ggplot2's reference page: four points on a discrete
# y axis, each labelled with its level, the labels nudged a tenth of a level down, geom_text()'s
# nudge_y. First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches
# but svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

data <- data.frame(x = c(1, 3, 2, 5), y = c("a", "c", "d", "c"))
plot <- ggplot(data, aes(x, y)) +
  geom_point() +
  geom_text(aes(label = y), nudge_y = -0.1) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
