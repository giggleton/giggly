# The plot test/golden/theme_family_geom_text.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_family_geom_text.R > theme_family_geom_text.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, which leaves
# out each label's font-family: vdiffr writes `sans` for every family and measures each with
# Liberation Sans, as Giggly measures it, where Giggly names the family.
#
# mtcars's cars by name at their weight and mileage, coloured by their cylinders, under a serif base
# family, which the layer's labels and the legend's keys take from the theme's `geom` element as
# its every text does.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

mtcars$model <- rownames(mtcars)

plot <- ggplot(mtcars, aes(wt, mpg, label = model, colour = factor(cyl))) +
  geom_text() +
  theme_gray(base_family = "serif")

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
