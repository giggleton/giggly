# The plot test/golden/raster_hole.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/raster_hole.R > raster_hole.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, setting aside
# each `<image>`'s data. The raster's `<image>` is compared by its attributes, which match but for
# its data's `href`, svglite's `xlink:href`, and by its pixels, decoded from each PNG
# (decompressed and unfiltered), which match byte for byte: the PNGs' bytes differ, as libpng and
# Erlang's zlib compress alike pixels differently.
#
# A raster with a hole and a missing value: x 1, 2 and 4, so the column at 3 is left clear, a
# transparent white pixel, as R writes `NA`; a fill missing at x 2, y 2, drawn in the scale's
# missing value, grey50; each cell blown up 142 by 246 pixels; the fill legend's keys filled over
# the whole key, unbordered, as `draw_key_polygon()` draws a raster's.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the axes
# drawn in test/golden/point.R's order, and the image's attributes and pixels match.

library(ggplot2)

df <- data.frame(
  x = c(1, 2, 4, 1, 2, 4),
  y = c(1, 1, 1, 2, 2, 2),
  z = c("a", "b", "c", "a", NA, "c")
)
plot <- ggplot(df, aes(x, y, fill = z)) +
  geom_raster() +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
