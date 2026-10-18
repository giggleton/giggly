# The plot test/golden/annotate.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/annotate.R > annotate.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# annotate()'s examples on six points: a band shaded from the panel's left edge to x = 2, top to
# bottom, its corners R's -Inf and Inf; the shaded rectangle under the points; the same text at
# each of four places; two labels taken in step with their positions and colours; and a label
# beyond the data, which the x and y axes reach. No annotation titles an axis. First checked with
# ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before the y as
# test/golden/point.R describes, and every clip path.

library(ggplot2)

data <- data.frame(
  wt = c(2.62, 2.32, 3.215, 3.44, 5.25, 1.615),
  mpg = c(21, 22.8, 21.4, 18.7, 10.4, 30.4)
)
plot <- ggplot(data, aes(wt, mpg)) +
  annotate("rect", xmin = -Inf, xmax = 2, ymin = -Inf, ymax = Inf, fill = "steelblue", alpha = 0.2) +
  annotate("rect", xmin = 3, xmax = 4.2, ymin = 12, ymax = 21, alpha = .2) +
  geom_point() +
  annotate("text", x = 2:5, y = 25, label = "Some text") +
  annotate("text", x = c(2, 3), y = c(15, 16), label = c("my label", "label 2"),
    colour = c("red", "blue")) +
  annotate("text", x = 6, y = 35, label = "beyond") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
