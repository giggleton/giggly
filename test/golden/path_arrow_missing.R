# The plot test/golden/path_arrow_missing.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/path_arrow_missing.R > path_arrow_missing.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A path broken by two missing positions, its first and last points each a piece of one point, with
# open heads at both ends: grid draws a polyline's heads only at the line's own first and last
# points, which here begin and end lone pieces, drawn as nothing, so no head is drawn at all; the
# middle piece has none. First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip
# path matches, the x axis drawn before the y as in test/golden/point.svg.

library(ggplot2)

df <- data.frame(x = 1:7, y = c(1, NA, 2, 3, 2, NA, 1))
plot <- ggplot(df, aes(x, y)) + geom_path(arrow = arrow(ends = "both")) + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
