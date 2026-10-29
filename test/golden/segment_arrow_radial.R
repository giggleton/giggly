# The plot test/golden/segment_arrow_radial.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/segment_arrow_radial.R > segment_arrow_radial.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Segments in radial coordinates with closed heads and `arrow.fill = "white"`: each drawn as a path,
# its head at the end of the munched line, and filled black, its line's colour, not white, since
# GeomSegment hands GeomPath its arrow without its arrow.fill. First checked with ggplot2 4.0.3 and
# vdiffr 1.0.9: every element matches, in order, and every clip path but svglite's around the whole
# drawing, as in test/golden/radial.R.

library(ggplot2)

df <- data.frame(x = c(1, 2), y = c(1, 3), xend = c(2, 3), yend = c(2, 1))
plot <- ggplot(df, aes(x, y, xend = xend, yend = yend)) +
  geom_segment(arrow = arrow(type = "closed"), arrow.fill = "white") +
  coord_radial() +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
