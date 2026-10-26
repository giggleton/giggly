# The plot test/golden/theme_text_strip_y.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_text_strip_y.R > theme_text_strip_y.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's city mileage against engine size in a row of panels per drive train, the strips right of
# them with their text level, a margin of 1, 2, 3 and 6 points round it, and no background.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, and every
# clip path matches.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, cty)) +
  geom_point() +
  facet_grid(drv ~ .) +
  theme_gray() +
  theme(
    strip.text.y = element_text(angle = 0, margin = margin(1, 2, 3, 6)),
    strip.background.y = element_blank()
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
