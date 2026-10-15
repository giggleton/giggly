# The plot test/golden/facet_wrap_free.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, which Docker's r-base image installs. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro r-base:latest bash -c \
#     'apt-get update -qq && apt-get install -y -qq r-cran-ggplot2 r-cran-vdiffr >/dev/null 2>&1 &&
#      Rscript /golden/facet_wrap_free.R' > facet_wrap_free.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes:
#
#   elements() { grep -E "^<(rect x|circle|polyline|text)" "$1" |
#     sed -e 's/font-family: [^;]*;//' -e 's/ stroke: #000000;//'; }
#   diff <(elements facet_wrap_free.ggplot2.svg) <(elements test/golden/facet_wrap_free.svg)
#
# Five panels with free scales, each on its own x and y scale, in two rows of three, the last row
# one short: every panel draws both axes, the first row's x axes are measured but for the one over
# the empty cell, and a left axis narrower than its column sits against its panel. Every element
# matches, in order, and so does every clip path, but for the plot background's left edge, which
# svglite writes as R's rounding error, `0.000000000000064`, and Giggly as `0.00`. First checked
# with ggplot2 4.0.3 and vdiffr 1.0.9.

library(ggplot2)

data <- data.frame(
  x = c(0, 10, 0, 1, 100, 200, 0, 4, 2, 3),
  y = c(0, 50, 0, 5, 0, 500, 10, 20, 0, 1000),
  g = c("a", "a", "b", "b", "c", "c", "d", "d", "e", "e")
)
plot <- ggplot(data, aes(x, y)) + geom_point() + facet_wrap(vars(g), scales = "free") + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
