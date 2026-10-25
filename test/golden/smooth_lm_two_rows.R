# The plot test/golden/smooth_lm_two_rows.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/smooth_lm_two_rows.R > smooth_lm_two_rows.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Weighted fits in two panels: one group's zero weight leaves it two rows, so it has no degrees
# of freedom and draws its line without a band; another holds one x and draws nothing.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, the x axis
# drawn before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
data <- data.frame(
  x = c(1, 2, 3, 1, 2, 3, 4, 2, 2),
  y = c(1, 3, 2, 2, 1, 4, 3, 5, 6),
  w = c(1, 1, 0, 2, 1, 1, 3, 1, 1),
  g = c("a", "a", "a", "b", "b", "b", "b", "c", "c"),
  panel = c("p", "p", "p", "q", "q", "q", "q", "q", "q")
)
plot <- ggplot(data, aes(x, y, weight = w, colour = g)) +
  geom_smooth(method = lm, formula = y ~ x) + facet_wrap(~panel) + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
