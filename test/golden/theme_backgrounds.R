# The plot test/golden/theme_backgrounds.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_backgrounds.R > theme_backgrounds.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# ggplot2's element reference page's "Backgrounds and margins" example: mpg's highway mileage
# against engine size, with the panel's background white, a 2 cm margin round the whole plot, and
# the plot's background light grey with a black border 1 mm wide. grey90 is #E5E5E5.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches once positions are
# rounded to two decimals (svglite writes the background's edge as R's rounding error), every clip
# path but svglite's around the whole drawing, and the one departure is test/golden/point.R's, the
# x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  theme_gray() +
  theme(
    panel.background = element_rect(fill = "white"),
    plot.margin = margin_auto(2, unit = "cm"),
    plot.background = element_rect(fill = "grey90", colour = "black", linewidth = 1)
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
