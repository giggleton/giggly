# The plot test/golden/smooth_gam.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/smooth_gam.R > smooth_gam.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A smooth given no method over diamonds' 53,940 rows, which ggplot2 fits by gam, drawn without
# the points: R's own gam, mgcv's "cs" shrinkage and its default REML, not test/golden/giggly_gam.R.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn
# before the y as test/golden/point.R describes, but the band and the line, within 0.13 points of
# R's, and the y axis's gridlines, ticks and labels, within 0.15, since the axis spans the band.
# The curve sits within 3.3e-4 of the range of price of R's and its standard errors within 1.7e-4,
# as mgcv's shrinkage turns on its rounding (design-log §4, the entry beginning "A gam's
# shrinkage"), so it is checked through its layer data, held to 1e-3, in test/giggly_test.exs.

library(ggplot2)
plot <- ggplot(diamonds, aes(carat, price)) + geom_smooth() + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
