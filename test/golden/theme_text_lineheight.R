# The plot test/golden/theme_text_lineheight.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_text_lineheight.R > theme_text_lineheight.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size under a two-line title, its lines 1.5 times
# theme_gray()'s spacing apart and right-aligned, and a two-line x title, its lines 0.6 apart.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  labs(title = "Fuel economy\nby engine size", x = "Engine displacement\n(litres)") +
  theme_gray() +
  theme(
    plot.title = element_text(lineheight = 1.5, hjust = 1),
    axis.title.x = element_text(lineheight = 0.6)
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
