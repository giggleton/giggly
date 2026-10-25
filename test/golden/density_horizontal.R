# The plot test/golden/density_horizontal.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/density_horizontal.R > density_horizontal.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# hwy mapped to y alone: the estimate runs up the panel, its outline along its right edge, and x
# takes the density.

library(ggplot2)
plot <- ggplot(mpg, aes(y = hwy)) + geom_density() + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
