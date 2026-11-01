# The plot test/golden/crossbar_looks.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/crossbar_looks.R > crossbar_looks.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R does.
#
# Crossbars filled by a mapped fill at half its alpha, their lines across and borders each given
# a look of their own, ended and joined round, 0.9 of a continuous axis's closest spacing wide.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

spaced <- data.frame(x = c(1, 2, 4), y = c(2, 3, 1), lo = c(1, 2.5, 0), hi = c(3, 4, 1.5),
  g = c("a", "b", "a"))

plot <- ggplot(spaced, aes(x, y, ymin = lo, ymax = hi, fill = g)) +
  geom_crossbar(alpha = 0.5, linewidth = 1, middle.colour = "red", middle.linetype = "dashed",
    box.colour = "blue", box.linewidth = 0.3, lineend = "round", linejoin = "round") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
