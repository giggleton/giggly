# The plot test/golden/pointrange_annotate.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/pointrange_annotate.R > pointrange_annotate.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R does.
#
# The reference page's annotated point range over mtcars' points, as annotate()'s page draws it.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

plot <- ggplot(mtcars, aes(x = wt, y = mpg)) + geom_point() +
  annotate("pointrange", x = 3.5, y = 20, ymin = 12, ymax = 28,
    colour = "red", size = 2.5, linewidth = 1.5) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
