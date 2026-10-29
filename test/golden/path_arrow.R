# The plot test/golden/path_arrow.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/path_arrow.R > path_arrow.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Two paths, colour mapped, with closed heads at both ends: each group's heads at its own ends,
# written right after its line, filled with its colour. First checked with ggplot2 4.0.3 and vdiffr
# 1.0.9: every element and clip path matches, the x axis drawn before the y as in
# test/golden/point.svg.

library(ggplot2)

df <- data.frame(
  x = c(1, 2, 3, 1, 2, 3), y = c(1, 2, 1, 2, 3, 2),
  g = c("a", "a", "a", "b", "b", "b")
)
plot <- ggplot(df, aes(x, y, colour = g)) +
  geom_path(arrow = arrow(type = "closed", ends = "both")) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
