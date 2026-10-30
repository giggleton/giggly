# The plot test/golden/hex.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2, vdiffr and hexbin, saved as the Docker image
# giggly-r:ggplot2-4.0.3-hexbin. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-hexbin \
#     Rscript /golden/hex.R > hex.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# mpg's engine sizes against highway mileage in hexagons, 30 across each axis, each filled by its
# count through the default continuous fill scale, unbordered, its legend a colour bar.
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and hexbin 1.28.6: every element and clip path
# matches but the colour bar's fill, vdiffr's device drawing no gradient
# (test/golden/point_colourbar.R checks Giggly's gradient against svglite's), and the one departure
# is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) + geom_hex() +
  guides(fill = guide_colourbar(display = "gradient")) + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
