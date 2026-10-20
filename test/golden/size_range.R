# The plot test/golden/size_range.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/size_range.R > size_range.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# The same points sized by area from 0 to 10 mm, as the reference page's `scale_size(range = c(0,
# 10))`: the legend's keys size themselves, the column as wide as the largest point, 9.35 mm or
# 26.52 points, and each row as tall as its own point or the theme's 17.28 points.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, size = hwy)) +
  geom_point() +
  scale_size_continuous(range = c(0, 10)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
