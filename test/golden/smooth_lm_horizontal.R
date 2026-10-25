# The plot test/golden/smooth_lm_horizontal.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/smooth_lm_horizontal.R > smooth_lm_horizontal.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A linear fit along y, displ fitted to hwy, as geom_smooth()'s reference page's orientation =
# "y": the line and its band run up the panel.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, the x axis
# drawn before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
plot <- ggplot(mpg, aes(displ, hwy)) + geom_point() +
  geom_smooth(method = lm, formula = y ~ x, orientation = "y") + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
