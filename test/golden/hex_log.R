# The plot test/golden/hex_log.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2, vdiffr and hexbin, saved as the Docker image
# giggly-r:ggplot2-4.0.3-hexbin. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-hexbin \
#     Rscript /golden/hex_log.R > hex_log.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# txhousing's monthly sales against their volume, both on log10 scales, in hexagons a tenth of a
# power of ten wide and high, the bin widths in the axes' transformed units; the rows missing
# either are left out.
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and hexbin 1.28.6: every element and clip path
# matches but the colour bar's fill, as test/golden/hex.R says, and the x axis's labels, which
# ggplot2 writes in scientific form (`1e+07`) and Giggly plainly (`10000000`), as Giggly writes
# every number (Scales.Labels.plain/1); the one other departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

plot <- ggplot(txhousing, aes(volume, sales)) + geom_hex(binwidth = 0.1) +
  scale_x_log10() + scale_y_log10() +
  guides(fill = guide_colourbar(display = "gradient")) + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
