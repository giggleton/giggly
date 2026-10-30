# The plot test/golden/scale_discrete_minor.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_discrete_minor.R > scale_discrete_minor.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage by class on a discrete x scale whose minor breaks are a function of two
# arguments, handed the axis's extent and the breaks' places, 1 to 7, that returns each place
# plus a half: a minor grid line between each class and the next and after the last.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the one
# departure test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(class, hwy)) +
  geom_point() +
  scale_x_discrete(minor_breaks = function(limits, breaks) breaks + 0.5) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
