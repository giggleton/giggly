# The plot test/golden/label_look.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/label_look.R > label_look.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A label's look: boxes filled by a mapped kind at half alpha, their text and dashed borders in
# red, which takes no alpha; and a second layer, nudged up, unfilled, its border blue and its text
# dark green, as `border.colour` and `text.colour` set them apart from `colour`. The fill's legend
# is left out.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

df <- data.frame(
  x = c(1, 2, 3, 4),
  y = c(1, 2, 1, 2),
  text = c("one", "two", "three", "four"),
  kind = c("a", "b", "a", "b")
)

plot <- ggplot(df, aes(x, y, label = text)) +
  geom_label(
    aes(fill = kind),
    alpha = 0.5, colour = "red", linetype = "dashed", linewidth = 0.8
  ) +
  geom_label(
    nudge_y = 0.3, fill = NA, border.colour = "blue", text.colour = "darkgreen"
  ) +
  guides(fill = "none") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
