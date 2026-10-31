# The plot test/golden/label_key_big.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/label_key_big.R > label_key_big.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A legend of labels 10 millimetres tall, filled by a mapped kind: each key is as big as
# draw_key_label() measures its letter's box, its padding a quarter of a line of grid's default
# 12-point font, 3.6 points, though the box is drawn padded by a quarter of a line of its own text,
# 8.54 points, so it spills out of its key, as R's does; and lifted by the descent of a 10-point
# font, as R hands font_descent() the size in millimetres.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

df <- data.frame(x = c(1, 2), y = c(1, 2), text = c("Ag", "b"), kind = c("u", "v"))

plot <- ggplot(df, aes(x, y, label = text, fill = kind)) +
  geom_label(size = 10) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
