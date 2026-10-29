# The plot test/golden/rug_sides.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/rug_sides.R > rug_sides.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Rugs along all four sides, given in another order than ggplot2 draws them, their colour mapped
# so the legend's keys are a path's, with round ends a millimetre wide; and an annotated rug along
# the right alone, in no legend.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.svg.

library(ggplot2)

df <- data.frame(x = c(1, 2, 3, 4), y = c(1, 3, 2, 4), g = c("a", "b", "a", "b"))
plot <- ggplot(df, aes(x, y, colour = g)) +
  geom_rug(sides = "lbrt", linewidth = 1, lineend = "round") +
  annotate("rug", y = c(1.5, 3.5), sides = "r", colour = "steelblue", length = unit(0.1, "npc")) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
