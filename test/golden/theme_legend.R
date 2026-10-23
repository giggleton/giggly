# The plot test/golden/theme_legend.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_legend.R > theme_legend.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A legend and strips set through the theme, on mpg's highway mileage against engine size by drive,
# in a panel per year: strips white with a black border and blue text with a margin on three of its
# sides, panels a line of text apart, keys a centimetre wide on white with a black border, labels
# 20 points and red, taller than their keys, with margins on every side, the title with margins on
# every side, the legend's margin a different width on each side, and the legends 3 mm from the
# panels.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_point() +
  facet_wrap(~year) +
  theme_gray() +
  theme(
    strip.background = element_rect(colour = "black", fill = "white"),
    strip.text = element_text(colour = "blue", margin = margin(t = 2, r = 8, b = 10, l = 0)),
    panel.spacing = unit(1, "lines"),
    legend.key = element_rect(fill = "white", colour = "black"),
    legend.text = element_text(
      size = 20, colour = "red", margin = margin(t = 3, r = 4, b = 1, l = 10)
    ),
    legend.title = element_text(margin = margin(t = 2, r = 30, b = 12, l = 6)),
    legend.key.width = unit(1, "cm"),
    legend.margin = margin(10, 4, 6, 2),
    legend.box.spacing = unit(3, "mm")
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
