# The plot test/golden/line_radial.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/line_radial.R > line_radial.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# A line through five points in radial coordinates: each piece changes both its angle and its
# radius, so ggplot2 munches it as the arc of Archimedes' spiral through its ends, cut into steps
# of a hundredth of the longest line a panel holds or less, and the line curves round the circle.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, with no
# departure, and every clip path but svglite's around the whole drawing, as in
# test/golden/radial.R.

library(ggplot2)

df <- data.frame(x = 1:5, y = c(1, 3, 2, 5, 4))
plot <- ggplot(df, aes(x, y)) + geom_line() + coord_radial() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
