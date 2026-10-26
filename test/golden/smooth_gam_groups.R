# The plot test/golden/smooth_gam_groups.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/smooth_gam_groups.R > smooth_gam_groups.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
# Its gam is fitted as Giggly fits one, by test/golden/giggly_gam.R.
#
# A gam for each drive, each band before its own line: the rear-wheel drives' 25 rows hold 9
# distinct displ, too few for 10 knots, so mgcv fails on them and ggplot2 draws them nothing, but
# their key.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, the x axis
# drawn before the y as test/golden/point.R describes, and every clip path.

source("/golden/giggly_gam.R")
plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_smooth(method = giggly_gam, formula = y ~ x) + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
