# The plot test/golden/linetype_economics.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/linetype_economics.R > linetype_economics.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# scale_linetype()'s own example: economics_long's five series, each rescaled 0 to 1, a line each
# in the first five of pal_linetype()'s line types, solid, 22, 42, 44 and 13, with a legend of
# their keys.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(economics_long, aes(date, value01)) +
  geom_line(aes(linetype = variable)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
