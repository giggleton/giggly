# The plot test/golden/legend_layer_keys.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_layer_keys.R > legend_layer_keys.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, `<line>`
# elements included.
#
# Points coloured by g, which holds a and b, and lines coloured by h, which holds a, b and c: one
# colour scale over both columns, and one legend, whose key c draws the line alone, since the
# points' column holds no c, as ggplot2 4's keep_key_data() leaves a layer out of a key its data
# lacks; the key's background and label stay.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

data <- data.frame(
  x = c(1, 2, 3, 4),
  y = c(1, 3, 2, 4),
  g = c("a", "b", "a", "b"),
  h = c("a", "b", "c", "c")
)
plot <- ggplot(data, aes(x, y)) +
  geom_point(aes(colour = g)) +
  geom_line(aes(colour = h)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
