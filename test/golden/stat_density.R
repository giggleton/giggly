# The plot test/golden/stat_density.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/stat_density.R > stat_density.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# stat_density() draws areas: each drive's estimate stacked, then, in a second layer drawn where
# each is, outlined in black along both edges, the lower one at 0, as an area of densities outlines
# them unless told otherwise.

library(ggplot2)
plot <- ggplot(mpg, aes(hwy, fill = drv)) + stat_density() +
  stat_density(colour = "black", position = "identity", alpha = 0.2, linetype = "dashed") +
  theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
