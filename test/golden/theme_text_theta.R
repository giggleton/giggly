# The plot test/golden/theme_text_theta.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_text_theta.R > theme_text_theta.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size in a radial panel, the labels round its circle turned
# 30 degrees and justified by their break's angle and that turn together, the radius axis's
# labels italic.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, and every clip path but
# svglite's around the whole drawing, as in test/golden/radial.R.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  coord_radial() +
  theme_gray() +
  theme(
    axis.text.theta = element_text(angle = 30),
    axis.text.r = element_text(face = "italic")
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
