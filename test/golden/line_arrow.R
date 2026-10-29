# The plot test/golden/line_arrow.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/line_arrow.R > line_arrow.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# ggplot2's geom_path() reference example: economics' population over time, a line with closed heads
# 15 degrees either side of it at both ends. First checked with ggplot2 4.0.3 and vdiffr 1.0.9:
# every element and clip path matches, the x axis drawn before the y as in test/golden/point.svg.

library(ggplot2)

c <- ggplot(economics, aes(x = date, y = pop))
plot <- c + geom_line(arrow = arrow(angle = 15, ends = "both", type = "closed")) + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
