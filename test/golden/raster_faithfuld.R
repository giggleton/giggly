# The plot test/golden/raster_faithfuld.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/raster_faithfuld.R > raster_faithfuld.ggplot2.svg
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
# geom_raster()'s first example: faithfuld's 75 by 75 grid of densities, each cell filled along
# the default gradient, drawn as one image of 600 by 525 pixels, each cell blown up 8 by 7 so it
# takes at least a pixel per point, and marked pixelated.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but the
# bar's fill, the axes drawn in test/golden/point.R's order, and the image's attributes and pixels
# match.

library(ggplot2)

plot <- ggplot(faithfuld, aes(waiting, eruptions)) +
  geom_raster(aes(fill = density)) +
  guides(fill = guide_colourbar(display = "gradient")) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
