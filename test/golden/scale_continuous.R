# The plot test/golden/scale_continuous.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_continuous.R > scale_continuous.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Continuous position scales' options on six points: an x scale named "Weight", which titles the
# axis over labs(), from 2 to 5, so the points at 1.615 and 5.25 are missing and not drawn, with
# its breaks given, 1.9 inside the widened axis though below the limits and 1 outside it, and two
# minor breaks given; a y scale with no labels, its ticks alone, and no room below its data.

library(ggplot2)

data <- data.frame(
  wt = c(2.62, 2.32, 3.215, 3.44, 5.25, 1.615),
  mpg = c(21, 22.8, 21.4, 18.7, 10.4, 30.4)
)
plot <- ggplot(data, aes(wt, mpg)) +
  geom_point() +
  labs(x = "not drawn") +
  scale_x_continuous(
    "Weight",
    limits = c(2, 5),
    breaks = c(1, 1.9, 3, 3.5, 5),
    minor_breaks = c(2.25, 4.25)
  ) +
  scale_y_continuous(labels = NULL, expand = expansion(mult = c(0, 0.05))) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
