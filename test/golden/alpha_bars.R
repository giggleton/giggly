# The plot test/golden/alpha_bars.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, which Docker's r-base image installs. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro r-base:latest bash -c \
#     'apt-get update -qq && apt-get install -y -qq r-cran-ggplot2 r-cran-vdiffr >/dev/null 2>&1 &&
#      Rscript /golden/alpha_bars.R' > alpha_bars.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes:
#
#   elements() { grep -E "^<(rect x|circle|polygon|polyline|text)" "$1" |
#     sed -e 's/font-family: [^;]*;//' -e 's/ stroke: #000000;//' -e 's/ fill: none;//'; }
#   diff <(elements alpha_bars.ggplot2.svg) <(elements test/golden/alpha_bars.svg)
#
# mpg's classes counted and shaded by drive train, a text alpha spread from 0.1 to 1 that also
# groups the bars, and the legend's keys drawn as bars, their fill short of the key by their
# border's width.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

# ggplot2 warns, on stderr, that alpha for a discrete variable is not advised.
plot <- ggplot(mpg, aes(class, alpha = drv)) + geom_bar() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
