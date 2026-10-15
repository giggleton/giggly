# The plot test/golden/radial.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, which Docker's r-base image installs. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro r-base:latest bash -c \
#     'apt-get update -qq && apt-get install -y -qq r-cran-ggplot2 r-cran-vdiffr >/dev/null 2>&1 &&
#      Rscript /golden/radial.R' > radial.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes:
#
#   elements() { grep -E "^<(rect x|circle|polygon|polyline|text)" "$1" |
#     sed -e 's/font-family: [^;]*;//' -e 's/ stroke: #000000;//' -e 's/ fill: none;//'; }
#   diff <(elements radial.ggplot2.svg) <(elements test/golden/radial.svg)
#
# The point golden's data in coord_radial()'s simplest form, its defaults. First checked with
# ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, with no departure; neither
# drawing clips the panel, coord_radial()'s default.

library(ggplot2)

data <- data.frame(wt = c(0, 4, 7, 10), mpg = c(0, 50, 20, NA))
plot <- ggplot(data, aes(wt, mpg)) + geom_point() + coord_radial() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
