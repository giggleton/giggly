# The plot test/golden/line_missing.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/line_missing.R > line_missing.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, lines
# included:
#
#   elements() { grep -E "^<(rect x|circle|polygon|polyline|line |text)" "$1" |
#     sed -e 's/font-family: [^;]*;//' -e 's/ stroke: #000000;//' -e 's/ fill: none;//'; }
#   diff <(elements line_missing.ggplot2.svg) <(elements test/golden/line_missing.svg)
#
# The "Missing values break a line" example on ggplot2's geom_path reference page: five points and
# a line through them, its third y missing, so the line is two polylines, each opaque, black and
# 0.5 mm wide with square-cut ends, and the point with no y is not drawn. First checked with
# ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but svglite's around the
# whole drawing, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

df <- data.frame(x = 1:5, y = c(1, 2, NA, 4, 5))
plot <- ggplot(df, aes(x, y)) + geom_point() + geom_line() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
