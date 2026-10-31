# The plot test/golden/tile_width.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/tile_width.R > tile_width.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_tile()'s second tile example: as test/golden/tile.R, but each tile as wide as its mapped
# width, so the tiles meet edge to edge from 0 to 14, which widens the x axis to them.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every rectangle, the tiles' and the keys',
# matches, the x axis drawn before the y as test/golden/point.R describes, and every clip path; the
# rest differs only as every golden does, by `fill: none` on lines and the font-family list.

library(ggplot2)

df <- data.frame(
  x = rep(c(2, 5, 7, 9, 12), 2),
  y = rep(c(1, 2), each = 5),
  z = factor(rep(1:5, each = 2)),
  w = rep(diff(c(0, 4, 6, 8, 10, 14)), 2)
)
plot <- ggplot(df, aes(x, y, width = w)) +
  geom_tile(aes(fill = z), colour = "grey50") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
