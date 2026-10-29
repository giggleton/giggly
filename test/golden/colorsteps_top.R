# The plot test/golden/colorsteps_top.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/colorsteps_top.R > colorsteps_top.ggplot2.svg
#
# and compare the drawing element by element, as test/golden/point.R describes.
#
# mtcars' mileage against weight coloured by horsepower on a continuous scale, its points along
# ggplot2's default gradient, read back by colour steps above the panel: running across, six bins
# of equal length cut at the scale's breaks and its limits, 52 and 335, each in the gradient's
# colour at its bin's middle, the breaks' labels below the bar, centred on their edges, its title
# left of it, and the black ticks the theme sets across its bottom and then its top, each drawn
# from inside the bar outward.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches vdiffr's,
# and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg, colour = hp)) +
  geom_point() +
  scale_colour_gradient(guide = "coloursteps") +
  theme_gray() +
  theme(legend.position = "top", legend.ticks = element_line(colour = "black"))

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
