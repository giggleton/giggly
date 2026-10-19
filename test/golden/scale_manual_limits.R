# The plot test/golden/scale_manual_limits.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_manual_limits.R > scale_manual_limits.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mtcars's weights by mileage coloured by their cylinders through a manual scale of named colours
# whose limits name a value the data lacks: its key, 10, is drawn on its background in orange,
# with no point in it, since no layer holds it; ggplot2's scale_manual page.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, the one departure test/golden/point.R's, the x axis drawn
# before the y.

library(ggplot2)

cols <- c("8" = "red", "4" = "blue", "6" = "darkgreen", "10" = "orange")
plot <- ggplot(mtcars, aes(mpg, wt)) +
  geom_point(aes(colour = factor(cyl))) +
  scale_colour_manual(values = cols, limits = c("4", "6", "8", "10")) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
