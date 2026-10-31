# The plot test/golden/raster_just.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/raster_just.R > raster_just.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, setting aside
# each `<image>`'s data. The raster's `<image>` is compared by its attributes, which match but for
# its data's `href`, svglite's `xlink:href`, and by its pixels, decoded from each PNG
# (decompressed and unfiltered), which match byte for byte: the PNGs' bytes differ, as libpng and
# Erlang's zlib compress alike pixels differently.
#
# Its colour bar is drawn in its gradient form (`display = "gradient"`), as Giggly draws one, which
# vdiffr writes as a rectangle with no fill: that `fill` is the one difference in the elements; the
# gradient itself is checked as test/golden/point_colourbar.R checks one.
#
# geom_raster()'s justification example: a 6 by 6 grid of R's `runif()` draws after `set.seed(1)`,
# each cell placed with `hjust = 0, vjust = 0`, so it lies left of and below its position, the axes
# widened to hold it.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: as test/golden/raster_faithfuld.R.

library(ggplot2)

set.seed(1)
df <- expand.grid(x = 0:5, y = 0:5)
df$z <- runif(nrow(df))
plot <- ggplot(df, aes(x, y, fill = z)) +
  geom_raster(hjust = 0, vjust = 0) +
  guides(fill = guide_colourbar(display = "gradient")) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
