# The plot test/golden/labs_lines.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/labs_lines.R > labs_lines.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Every label labs() sets, each over two lines, on a faceted plot: mpg's highway mileage against
# engine size in a panel for each year, coloured by drive train. Each line is drawn by itself, the
# theme's line height, 0.9, apart; the title, subtitle and caption span the panels. First checked
# with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but svglite's around the
# whole drawing; a faceted plot draws its axes in Giggly's order.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_point() +
  facet_wrap(~year) +
  labs(
    title = "Fuel economy\nby engine size",
    subtitle = "Highway mileage,\nby year",
    caption = "Source:\nggplot2's mpg",
    tag = "A\nB",
    x = "Engine\ndisplacement (l)",
    y = "Highway\nmpg",
    colour = "Drive\ntrain"
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
