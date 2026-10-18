# The plot test/golden/labs_untitled.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/labs_untitled.R > labs_untitled.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A colour bar and a legend whose titles labs() removes, and the room the titles took: mtcars' fuel
# economy against weight, coloured by quarter-mile time and given an alpha by gears, the colour bar
# in its gradient form, as test/golden/point_colourbar.R draws one. First checked with ggplot2
# 4.0.3 and vdiffr 1.0.9: every element and clip path matches but svglite's around the whole
# drawing and the colour bar's fill, which vdiffr's device cannot draw
# (test/golden/point_colourbar.R checks the gradient), and the one departure is
# test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

cars <- data.frame(
  wt = mtcars$wt,
  mpg = mtcars$mpg,
  qsec = mtcars$qsec,
  gear = as.character(mtcars$gear)
)
plot <- ggplot(cars, aes(wt, mpg, colour = qsec, alpha = gear)) +
  geom_point() +
  labs(colour = NULL, alpha = NULL) +
  guides(
    alpha = guide_legend(order = 1),
    colour = guide_colourbar(display = "gradient", order = 2)
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
