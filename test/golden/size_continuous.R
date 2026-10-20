# The plot test/golden/size_continuous.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/size_continuous.R > size_continuous.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# scale_size()'s first example from ggplot2's reference page: mpg's highway mileage drawn as
# each point's size, by area from 1 to 6 mm, and a legend of three points at the breaks 20, 30
# and 40, each in a key of the theme's 17.28 points, the largest point fitting.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, size = hwy)) +
  geom_point() +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
