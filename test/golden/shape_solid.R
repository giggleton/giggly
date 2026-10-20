# The plot test/golden/shape_solid.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/shape_solid.R > shape_solid.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# scale_shape()'s first example: a hundred diamonds picked at random after set.seed(596), their
# price by carat, each cut in one of the palette's solid shapes. Its cut is an ordered factor,
# which ggplot2 gives scale_shape_ordinal(), warning and drawing as scale_shape() does; Giggly's
# test takes the same rows and gives the scale cut's levels as its limits, which Giggly's column of
# strings would otherwise sort alphabetically.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

set.seed(596)
dsmall <- diamonds[sample(nrow(diamonds), 100), ]

plot <- ggplot(dsmall, aes(carat, price)) + geom_point(aes(shape = cut)) + theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
