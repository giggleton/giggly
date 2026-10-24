# The plot test/golden/theme_text_axis_x_negative.svg draws, drawn by ggplot2 itself, as ggplot2's
# own visual tests draw their snapshots: the independent check on that golden whenever it changes.
# The suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_text_axis_x_negative.R > theme_text_axis_x_negative.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# The ggplot2 book's long labels (Themes, "Axis"), turned 30 degrees clockwise, each starting at
# its tick (`angle = -30, vjust = 1, hjust = 0`), with no axis titles.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

df <- data.frame(
  x = c("label", "a long label", "an even longer label"),
  y = 1:3
)

plot <- ggplot(df, aes(x, y)) +
  geom_point() +
  theme_gray() +
  theme(axis.text.x = element_text(angle = -30, vjust = 1, hjust = 0)) +
  xlab(NULL) +
  ylab(NULL)

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
