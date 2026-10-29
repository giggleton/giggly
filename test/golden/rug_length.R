# The plot test/golden/rug_length.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/rug_length.R > rug_length.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Rugs of a length in points along the top and right, and of a share of the panel along the
# bottom and left, dashed: a row missing its x draws only its y's line, one missing its y only its
# x's, and an infinite x is at the panel's corner.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.svg.

library(ggplot2)

df <- data.frame(x = c(1, NA, 3, Inf, 2), y = c(10, 20, NA, 40, 30))
plot <- ggplot(df, aes(x, y)) +
  geom_rug(sides = "tr", length = unit(12, "pt"), colour = "red") +
  geom_rug(length = unit(0.05, "npc"), linetype = "dashed") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
