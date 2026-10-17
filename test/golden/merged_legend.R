# The plot test/golden/merged_legend.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/merged_legend.R > merged_legend.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Columns filled by g and points coloured by it: the fill's legend and the colour's have one title
# and one set of labels, so they merge into one, each key drawn by both layers, the column's in its
# fill alone and the point's in its colour alone.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

data <- data.frame(x = c(1, 2, 3), y = c(2, 3, 1), g = c("b", "a", "b"))
plot <- ggplot(data, aes(x, y)) +
  geom_col(aes(fill = g)) +
  geom_point(aes(colour = g)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
