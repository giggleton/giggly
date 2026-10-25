# The plot test/golden/density_stacked.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/density_stacked.R > density_stacked.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Each drive's count, its density times its rows, stacked, so the curves pile up to the density of
# every car times their number, as the geom_density() reference page stacks diamonds' cuts.

library(ggplot2)
plot <- ggplot(mpg, aes(hwy, after_stat(count), fill = drv)) +
  geom_density(position = "stack") + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
