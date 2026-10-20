# The plot test/golden/text_key_turned.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/text_key_turned.R > text_key_turned.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# The same labels at size 8 mm, turned 30 degrees and justified `hjust = 0, vjust = 1`: each key
# as big as the box round its turned letter, its descent and its margins, 24.04 by 26.87 points,
# and the letter placed at its justification turned with it, a tenth of a line of its own text in
# from the key's edges.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv, label = drv)) +
  geom_text(size = 8, angle = 30, hjust = 0, vjust = 1) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
