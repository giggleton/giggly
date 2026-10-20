# The plot test/golden/count_prop.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/count_prop.R > count_prop.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_count()'s proportions, as its diamonds examples draw them, on mpg's classes and drive
# trains: one group of every row, each point sized by its share of all of them, by area up to
# 10 mm, the legend titled prop.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches but the background's
# edge, which svglite writes as R's rounding error, the x axis drawn before the y as
# test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(mpg, aes(class, drv)) +
  geom_count(aes(size = after_stat(prop), group = 1)) +
  scale_size_area(max_size = 10) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
