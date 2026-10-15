# The plot test/golden/facet_wrap.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, which Docker's r-base image installs. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro r-base:latest bash -c \
#     'apt-get update -qq && apt-get install -y -qq r-cran-ggplot2 r-cran-vdiffr >/dev/null 2>&1 &&
#      Rscript /golden/facet_wrap.R' > facet_wrap.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes:
#
#   elements() { grep -E "^<(rect x|circle|polygon|polyline|text)" "$1" |
#     sed -e 's/font-family: [^;]*;//' -e 's/ stroke: #000000;//' -e 's/ fill: none;//'; }
#   diff <(elements facet_wrap.ggplot2.svg) <(elements test/golden/facet_wrap.svg)
#
# Five combinations of two columns make five panels in two rows of three, the last row one short,
# so the panel above the empty cell draws an axis that hangs into it, and each panel has two strips.
# Every element matches, in order, and so does every clip path (the panels' and each strip's), but
# for the plot background's left edge, which svglite writes as R's rounding error,
# `-0.000000000000064`, and Giggly as `0.00`. First checked with ggplot2 4.0.3 and vdiffr 1.0.9.

library(ggplot2)

data <- data.frame(
  wt = c(0, 4, 7, 10, 2, 5, 8, 3, 6),
  mpg = c(0, 50, 20, 35, 10, 40, 25, 15, 30),
  cyl = c(4, 4, 4, 6, 6, 6, 8, 8, 8),
  drv = c("f", "r", "r", "4", "4", "f", "f", "f", "f")
)
plot <- ggplot(data, aes(wt, mpg)) + geom_point() + facet_wrap(vars(cyl, drv)) + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
