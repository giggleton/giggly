# The plot test/golden/text_legend.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/text_legend.R > text_legend.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Each car's name in its number of cylinders' hue, half opaque, turned 45 degrees about its middle;
# the legend's keys are the letter "a" in each hue at the layer's alpha, turned with the labels. The
# cylinders are written as text, `as.character()`, so the legend is titled `cyl`. First checked with
# ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but svglite's around the whole
# drawing, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

cars <- data.frame(
  model = rownames(mtcars),
  wt = mtcars$wt,
  mpg = mtcars$mpg,
  cyl = as.character(mtcars$cyl)
)

plot <- ggplot(cars, aes(wt, mpg, label = model, colour = cyl)) +
  geom_text(angle = 45, alpha = 0.5) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
