# The plot test/golden/hex_bins.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2, vdiffr and hexbin, saved as the Docker image
# giggly-r:ggplot2-4.0.3-hexbin. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-hexbin \
#     Rscript /golden/hex_bins.R > hex_bins.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Hexagons 10 across x and 5 up y, written as the widths that number gives each axis, the axis's
# extent over its bins, as ggplot2's documentation describes `bins = c(10, 5)`; ggplot2 4.0.3
# divides x's extent for both, so the pair itself would draw something else.
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and hexbin 1.28.6: every element and clip path
# matches but the colour bar's fill, as test/golden/hex.R says, and the one departure is
# test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_hex(binwidth = c(diff(range(mpg$displ)) / 10, diff(range(mpg$hwy)) / 5)) +
  guides(fill = guide_colourbar(display = "gradient")) + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
