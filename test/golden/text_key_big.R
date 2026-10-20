# The plot test/golden/text_key_big.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/text_key_big.R > text_key_big.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's drive trains written at each point, coloured by drive train, at size 12 mm: each colour
# key is the letter "a" at 34.14 points, its key 21.87 points wide and 33.47 tall, the letter's
# width and its ascent and descent with a margin of 1.44 points each side, a tenth of a line of
# grid's default 12-point font, as `draw_key_text()` measures it.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv, label = drv)) +
  geom_text(size = 12) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
