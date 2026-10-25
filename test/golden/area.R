# The plot test/golden/area.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/area.R > area.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_area()'s default look over one group, from coord_flip()'s reference page: filled with the
# theme's ink mixed 20% toward its paper, its upper edge a line of no colour.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn
# before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
data <- data.frame(a = 1:5, b = (1:5)^2)
plot <- ggplot(data, aes(a, b)) + geom_area() + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
