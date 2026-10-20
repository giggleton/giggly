# The plot test/golden/point_fill_legend.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/point_fill_legend.R > point_fill_legend.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage by displacement, each point shape 21, 3 mm, filled by its drive train from
# the plot's mapping, and the legend's keys drawn in the layer's shape and size, each filled with
# its break's colour. First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches,
# in the same order, the x axis drawn before the y as test/golden/point.R describes, and every clip
# path.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, fill = drv)) +
  geom_point(shape = 21, size = 3) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
