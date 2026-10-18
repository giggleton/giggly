# The plot test/golden/rect.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/rect.R > rect.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_rect()'s "Rectangles by their corners" example, its corners worked out in the table rather
# than in the mapping, as R's example computes them: each rectangle filled by its level and bordered
# in grey50, the fill legend's keys drawn as rectangles; and a second layer of one row whose corners
# are set, from the panel's foot (R's -Inf) up to 2, which widens the x axis to 16. Mapping only
# corners, the plot titles neither axis. First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every
# element matches, the x axis drawn before the y as test/golden/point.R describes, and every clip
# path.

library(ggplot2)

df <- data.frame(
  x = rep(c(2, 5, 7, 9, 12), 2),
  y = rep(c(1, 2), each = 5),
  z = factor(c(rep(1:4, each = 2), 5, 6)),
  w = rep(diff(c(0, 4, 6, 8, 10, 14)), 2)
)
corners <- data.frame(
  left = df$x - df$w / 2, right = df$x + df$w / 2, bottom = df$y, top = df$y + 1, z = df$z
)
plot <- ggplot(corners, aes(xmin = left, xmax = right, ymin = bottom, ymax = top)) +
  geom_rect(aes(fill = z), colour = "grey50") +
  geom_rect(data = data.frame(a = 1), xmin = 14, xmax = 16, ymin = -Inf, ymax = 2,
    fill = "steelblue") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
