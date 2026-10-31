# The plot test/golden/label_key_turned.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/label_key_turned.R > label_key_turned.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A legend of labels turned 120 degrees and hung by their start and top, 8 millimetres tall,
# padded 6 points on boxes of 3-point corners, filled by a mapped kind at alpha 0.4, their borders
# dashed red and their text blue: each key's letter is placed at its justification turned with the
# text, as rotate_just() turns it, and its key is as big as the box turned with it.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

df <- data.frame(x = c(1, 2), y = c(1, 2), text = c("Ag", "b"), kind = c("u", "v"))

plot <- ggplot(df, aes(x, y, label = text, fill = kind)) +
  geom_label(
    angle = 120, hjust = 0, vjust = 1, size = 8, alpha = 0.4, linetype = "dashed",
    label.padding = unit(6, "pt"), label.r = unit(3, "pt"),
    border.colour = "red", text.colour = "blue"
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
