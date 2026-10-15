# The plot test/golden/point.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, which Docker's r-base image installs. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro r-base:latest bash -c \
#     'apt-get update -qq && apt-get install -y -qq r-cran-ggplot2 r-cran-vdiffr >/dev/null 2>&1 &&
#      Rscript /golden/point.R' > point.ggplot2.svg
#
# and compare the two drawings element by element, leaving out what svglite writes and Giggly does
# not (its XML declaration, its stylesheet, its page rectangle and its clip groups), each label's
# font-family, and a circle's black stroke and a polyline's `fill: none`, which svglite leaves to
# its stylesheet:
#
#   elements() { grep -E "^<(rect x|circle|polygon|polyline|text)" "$1" |
#     sed -e 's/font-family: [^;]*;//' -e 's/ stroke: #000000;//' -e 's/ fill: none;//'; }
#   diff <(elements point.ggplot2.svg) <(elements test/golden/point.svg)
#
# vdiffr's `write_svg()` draws with its own copy of svglite and the Liberation fonts, at 720 by 576
# points, with no title; `theme_gray()` is added because vdiffr gives a plot that sets no theme
# `theme_test()` instead. First checked with ggplot2 4.0.3 and vdiffr 1.0.9.
#
# The diff shows one difference, by design: Giggly draws the x axis before the y axis, the order
# ggplot2's facets draw axes in, where ggplot2's plot without a facet draws the y axis first; the
# two never overlap, so the drawings look the same, and every element matches.

library(ggplot2)

data <- data.frame(wt = c(0, 4, 7, 10), mpg = c(0, 50, 20, NA))
plot <- ggplot(data, aes(wt, mpg)) + geom_point() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
