# The plot test/golden/area_stacked.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/area_stacked.R > area_stacked.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# position_stack()'s stacked areas from ggplot2's reference page: four groups at the same four
# times, each aligned at every time and 0.003 either side and padded to 0 at its ends, piled with
# the first group on top, the upper edge leaving the padding out; the legend's keys are each
# fill's rectangle with round corners, as draw_key_polygon() takes the layer's linejoin.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn
# before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
series <- data.frame(time = rep(1:4, each = 4), type = rep(c("a", "b", "c", "d"), 4),
  value = c(8, 10, 7, 11, 14, 12, 11, 9, 14, 11, 8, 2, 8, 10, 7, 12))
plot <- ggplot(series, aes(time, value)) + geom_area(aes(fill = type)) + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
