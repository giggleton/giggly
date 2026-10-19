# The plot test/golden/legend_continuous_reverse.svg draws, drawn by ggplot2 itself, as ggplot2's
# own visual tests draw their snapshots: the independent check on that golden whenever it changes.
# The suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_continuous_reverse.R > legend_continuous_reverse.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mtcars's weights by mileage coloured by horsepower along the default gradient, read back by a
# legend rather than a colour bar, its keys reversed: a key for each break, the highest at the top.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9.

library(ggplot2)

plot <- ggplot(mtcars, aes(mpg, wt, colour = hp)) +
  geom_point() +
  scale_colour_gradient(guide = guide_legend(reverse = TRUE)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
