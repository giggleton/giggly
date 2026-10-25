# The plot test/golden/density.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/density.R > density.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_density()'s estimate of mpg's highway mileage: one curve across the whole x axis, outlined
# along its top in the theme's ink and left unfilled.

library(ggplot2)
plot <- ggplot(mpg, aes(hwy)) + geom_density() + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
