# The plot test/golden/annotate_label.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/annotate_label.R > annotate_label.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Labels annotated over six points, each list one value per label: the first filled light yellow
# at half alpha, its border red, dashed and 1 mm wide; the second unfilled, its text and border
# dark green; the third filled pink in no colour, so its box is drawn with no border and its text
# in no colour, its border dotted and 0 wide, so none. Then one label beyond the data, which the
# axes reach, turned, larger, its text blue apart from its border. First checked with ggplot2
# 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the one departure is
# test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

data <- data.frame(
  wt = c(2.62, 2.32, 3.215, 3.44, 5.25, 1.615),
  mpg = c(21, 22.8, 21.4, 18.7, 10.4, 30.4)
)
plot <- ggplot(data, aes(wt, mpg)) +
  geom_point() +
  annotate("label", x = c(2, 3, 4), y = c(15, 20, 25), label = c("first", "second", "third"),
    fill = c("lightyellow", NA, "pink"), colour = c("red", "darkgreen", NA),
    alpha = c(0.5, 1, 1), linewidth = c(1, 0.25, 0), linetype = c("dashed", "solid", "dotted")) +
  annotate("label", x = 6, y = 35, label = "beyond", size = 6, angle = 15, text.colour = "blue") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
