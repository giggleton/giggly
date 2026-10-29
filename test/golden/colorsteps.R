# The plot test/golden/colorsteps.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/colorsteps.R > colorsteps.ggplot2.svg
#
# and compare the drawing element by element, as test/golden/point.R describes. vdiffr's device
# draws the bins' rectangles, so nothing is checked against svglite.
#
# mtcars' mileage against weight coloured by horsepower on ggplot2's default binned scale, its
# limits widened from the data's 52 to 335 to 50 to 350 so the end bins are as wide as their
# neighbours, and its colour steps guide: six bins of equal length up a bar five keys long, each
# in the colour of its bin's middle, the breaks' labels at the edges between them, and no ticks.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches vdiffr's,
# and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg, colour = hp)) +
  geom_point() +
  scale_colour_binned() +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
