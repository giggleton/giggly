# The plot test/golden/col_fill_colour.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/col_fill_colour.R > col_fill_colour.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# position_dodge's reference page's example of columns dodged by group, filled in a fixed colour
# and bordered in another: R's grey50, which CSS has no name for, so Giggly's plot writes its hex,
# #7F7F7F, and black. First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip
# path matches but svglite's around the whole drawing, and the one departure is
# test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

df <- data.frame(
  x = c("a", "a", "b", "b"),
  y = 2:5,
  g = rep(1:2, 2)
)
plot <- ggplot(df, aes(x, y, group = g)) +
  geom_col(position = "dodge", fill = "grey50", colour = "black") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
