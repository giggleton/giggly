# The plot test/golden/theme_blank.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_blank.R > theme_blank.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# ggplot2's element reference page's "Blank elements" example: mpg's highway mileage against engine
# size with the panel's background and the axes' tick labels removed, so the panel is drawn on the
# plot's white and each axis keeps only its ticks' room, as a scale with no labels does.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  theme_gray() +
  theme(
    panel.background = element_blank(),
    axis.text = element_blank()
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
