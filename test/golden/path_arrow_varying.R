# The plot test/golden/path_arrow_varying.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/path_arrow_varying.R > path_arrow_varying.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# One path whose colour changes along it, open heads at both ends: drawn as segments, each given a
# head as ggplot2's repair_segment_arrow() gives one, so the first segment's head is at its first
# end, the last's at its last, and the middle one's at both ends with no length, written as three
# points at its tip, as grid draws a head of no length. First checked with ggplot2 4.0.3 and vdiffr
# 1.0.9: every element and clip path matches, the x axis drawn before the y as in
# test/golden/point.svg.

library(ggplot2)

df <- data.frame(x = c(1, 2, 3, 4), y = c(1, 2, 3, 4), c = c("a", "a", "b", "b"))
plot <- ggplot(df, aes(x, y, colour = c, group = 1)) +
  geom_path(arrow = arrow(ends = "both")) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
