# The plot test/golden/theme_text_axis_x_90.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_text_axis_x_90.R > theme_text_axis_x_90.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage by class as box plots, each class's label turned on its side, ending at
# its tick and centred across it (`hjust = 1, vjust = 0.5`), the axis as deep as the widest label.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(class, hwy)) +
  geom_boxplot() +
  theme_gray() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
