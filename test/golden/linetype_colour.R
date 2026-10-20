# The plot test/golden/linetype_colour.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/linetype_colour.R > linetype_colour.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# economics_long's five series mapped to line type and to colour: one legend, each key its line
# type in its colour.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(economics_long, aes(date, value01, linetype = variable, colour = variable)) +
  geom_line() +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
