# The plot test/golden/smooth_lm_fullrange.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/smooth_lm_fullrange.R > smooth_lm_fullrange.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Each drive's fit over the whole of the x axis's extent, a 99% band, set fill, alpha, width and
# line type, and ends and corners of the layer's own: the lines reach the panel's sides, short of
# its widening, and the keys carry the set look.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, the x axis
# drawn before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_smooth(method = lm, formula = y ~ x, fullrange = TRUE, level = 0.99, fill = "orange",
    alpha = 0.2, linewidth = 2, linetype = "dashed", lineend = "round", n = 20) +
  theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
