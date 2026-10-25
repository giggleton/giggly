# The plot test/golden/density_bounds.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/density_bounds.R > density_bounds.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Highway mileage known to be 12 or more: the unbounded estimate in red spills below 12, and the
# bounded one in blue folds that part back inside, on twice the places, as the geom_density()
# reference page bounds diamonds' carats.

library(ggplot2)
plot <- ggplot(mpg, aes(hwy)) + geom_density(colour = "red") +
  geom_density(bounds = c(12, Inf), colour = "blue") + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
