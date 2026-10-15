# The plot test/golden/horizontal_bar.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, which Docker's r-base image installs. From the repository's
# root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro r-base:latest bash -c \
#     'apt-get update -qq && apt-get install -y -qq r-cran-ggplot2 r-cran-vdiffr >/dev/null 2>&1 &&
#      Rscript /golden/horizontal_bar.R' > horizontal_bar.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes:
#
#   elements() { grep -E "^<(rect x|circle|polygon|polyline|text)" "$1" |
#     sed -e 's/font-family: [^;]*;//' -e 's/ stroke: #000000;//' -e 's/ fill: none;//'; }
#   diff <(elements horizontal_bar.ggplot2.svg) <(elements test/golden/horizontal_bar.svg)
#
# geom_bar()'s third example from ggplot2's reference page: mpg's classes counted along y, so the
# bars run rightward and the x axis is titled count. First checked with ggplot2 4.0.3 and vdiffr
# 1.0.9: every element and clip path matches but svglite's around the whole drawing, and the one
# departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg) + geom_bar(aes(y = class)) + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
