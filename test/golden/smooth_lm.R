# The plot test/golden/smooth_lm.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/smooth_lm.R > smooth_lm.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_smooth()'s linear fit over mpg's points, as geom_smooth()'s reference page draws it with
# method = lm: the band in the theme's ink mixed 60% toward its paper at alpha 0.4, then the line
# in the theme's accent, twice the lines' width.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, the x axis
# drawn before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
plot <- ggplot(mpg, aes(displ, hwy)) + geom_point() +
  geom_smooth(method = lm, formula = y ~ x) + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
