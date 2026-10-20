# The plot test/golden/count_colour.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/count_colour.R > count_colour.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Counts coloured by drive train: a point for each drive train at each pair of mileages, the
# colour legend beside the size legend, which ggplot2 orders by a hash, so guides() orders them
# as Giggly does, by their aesthetics' names.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn before
# the y as test/golden/point.R describes, and every clip path.

library(ggplot2)

plot <- ggplot(mpg, aes(cty, hwy, colour = drv)) +
  geom_count() +
  guides(colour = guide_legend(order = 1), size = guide_legend(order = 2)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
