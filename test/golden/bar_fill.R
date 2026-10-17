# The plot test/golden/bar_fill.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/bar_fill.R > bar_fill.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_bar()'s example from ggplot2's reference page: mpg's classes counted, each bar stacked by
# drive train and filled in its hue, and a legend of the fills, each key a bar's fill short of the
# key by its border's width.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y. ggplot2 evaluates the layer's fill before the plot's x, so the bars are
# numbered, and drawn, by drive train first, as Giggly's are.

library(ggplot2)

plot <- ggplot(mpg, aes(class)) + geom_bar(aes(fill = drv)) + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
