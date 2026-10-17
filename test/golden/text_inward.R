# The plot test/golden/text_inward.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/text_inward.R > text_inward.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_text()'s "Justification" example from ggplot2's reference page: five labels at the corners
# and middle of the data, each justified `"inward"` both ways, so the ones at the corners sit inside
# the panel against their corner and the one in the middle is centred on it. First checked with
# ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but svglite's around the
# whole drawing, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

df <- data.frame(
  x = c(1, 1, 2, 2, 1.5),
  y = c(1, 2, 1, 2, 1.5),
  text = c("bottom-left", "top-left", "bottom-right", "top-right", "center")
)

plot <- ggplot(df, aes(x, y)) +
  geom_text(aes(label = text), vjust = "inward", hjust = "inward") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
