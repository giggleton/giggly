# The plot test/golden/smooth_gam_fullrange.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/smooth_gam_fullrange.R > smooth_gam_fullrange.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
# Its gam is fitted as Giggly fits one, by test/golden/giggly_gam.R.
#
# A gam across the full range of an x axis from 0 to 10: past displ's 1.6 and 7, its outermost
# knots, the curve runs straight on at its slope there, and its band widens.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, the x axis
# drawn before the y as test/golden/point.R describes, and every clip path.

source("/golden/giggly_gam.R")
plot <- ggplot(mpg, aes(displ, hwy)) + geom_point() +
  geom_smooth(method = giggly_gam, formula = y ~ x, fullrange = TRUE) + xlim(0, 10) + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
