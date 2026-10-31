# The plot test/golden/abline_keys.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/abline_keys.R > abline_keys.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Diagonal lines mapped from a table of their own, a line or two in each panel of mtcars' points
# faceted by cylinders, their colour and line type mapped into one legend, each key
# `draw_key_abline()`'s, from the key's bottom left corner to its top right, ended square.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, and every
# clip path.

library(ggplot2)

lines <- data.frame(
  cyl = c(4, 6, 8, 8),
  intercept = c(40, 30, 25, 20),
  slope = c(-5, -3, -2, -1),
  kind = c("steep", "steep", "steep", "shallow")
)

plot <- ggplot(mtcars, aes(wt, mpg)) + geom_point() +
  geom_abline(aes(intercept = intercept, slope = slope, colour = kind, linetype = kind),
    data = lines, lineend = "square") +
  facet_wrap(~cyl) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
