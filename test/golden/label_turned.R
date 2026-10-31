# The plot test/golden/label_turned.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/label_turned.R > label_turned.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Labels turned with their boxes: one layer turned 30 degrees and hung from its place by its start
# and top, and one turned 200 degrees, justified inward along its baseline and outward up it, on
# boxes padded a millimetre with corners of 4 points, in blue.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

df <- data.frame(x = c(1, 2, 3), y = c(1, 3, 2), text = c("Ag", "turned", "Wy"))

plot <- ggplot(df, aes(x, y, label = text)) +
  geom_label(angle = 30, hjust = 0, vjust = 1) +
  geom_label(
    angle = 200, hjust = "inward", vjust = "outward",
    label.padding = unit(1, "mm"), label.r = unit(4, "pt"), colour = "blue"
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
