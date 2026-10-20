# The plot test/golden/size_area.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/size_area.R > size_area.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# The same points sized by `scale_size_area()`: each point's area in proportion to its mileage,
# 0 at size 0 and the highest, 44, at 6 mm, so the smallest, 12, is drawn at 3.13 mm.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, size = hwy)) +
  geom_point() +
  scale_size_area() +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
