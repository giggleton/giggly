# The plot test/golden/theme_bw.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_bw.R > theme_bw.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size, coloured by fuel, a panel for each drive, in
# theme_bw(): each panel white and bordered dark grey over its points, its grid lines light grey,
# each strip light grey bordered as the panels are, cut to half its border by its clipping, and the
# legend's keys white.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, in
# ggplot2's order.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = fl)) +
  geom_point() +
  facet_wrap(~drv, ncol = 2) +
  labs(title = "Title", subtitle = "Subtitle", caption = "Caption", tag = "A") +
  theme_bw()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
