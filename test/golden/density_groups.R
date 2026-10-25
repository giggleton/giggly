# The plot test/golden/density_groups.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/density_groups.R > density_groups.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A curve for each drive, filled and outlined in its colour, the fill at alpha 0.3, with xlim()
# cutting the rows outside 15 to 40 before the estimate, as the geom_density() reference page's
# diamonds example cuts depth; the keys an area's, filled and bordered.

library(ggplot2)
plot <- ggplot(mpg, aes(hwy, fill = drv, colour = drv)) + geom_density(alpha = 0.3) +
  xlim(15, 40) + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
