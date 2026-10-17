# The plot test/golden/text.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/text.R > text.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_text()'s "Avoid overlaps" example from ggplot2's reference page: each car's name at its
# weight and mileage, black and 11 points, centred on its place, and each name that would cross one
# drawn before it, in the order of the rows, left out (8 of the 32). First checked with ggplot2
# 4.0.3 and vdiffr 1.0.9: every element and clip path matches but svglite's around the whole
# drawing, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg, label = rownames(mtcars))) +
  geom_text(check_overlap = TRUE) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
