# The plot test/golden/scale_discrete.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_discrete.R > scale_discrete.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage by class on a discrete x scale named "Class", which titles the axis,
# showing suv, wagon and compact in that order: the classes it leaves out are not drawn, wagon,
# which mpg lacks, leaves its place empty, and suv is labelled by value.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the one
# departure test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(class, hwy)) +
  geom_point() +
  scale_x_discrete("Class", limits = c("suv", "wagon", "compact"), labels = c(suv = "SUV")) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
