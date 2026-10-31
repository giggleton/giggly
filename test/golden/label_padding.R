# The plot test/golden/label_padding.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/label_padding.R > label_padding.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A label's padding given side by side, 2 points above, 8 right, 4 below and 1 left, at 6
# millimetres, on square corners with no border; an empty label drawing its padding alone; and a
# second layer, nudged up, of no colour, which keeps its white box but draws neither its text nor
# its border.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

df <- data.frame(x = c(1, 2, 3), y = c(1, 2, 3), text = c("Ag", "", "b"))

plot <- ggplot(df, aes(x, y, label = text)) +
  geom_label(
    label.padding = margin(2, 8, 4, 1), label.r = unit(0, "pt"), linewidth = 0, size = 6
  ) +
  geom_label(nudge_y = 0.4, colour = NA) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
