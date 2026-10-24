# The plot test/golden/theme_text_strip.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_text_strip.R > theme_text_strip.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size in a panel per class, each strip's label bold and at
# its strip's left, its margin in.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches once positions are
# rounded to two decimals (svglite writes the background's edge as R's rounding error), every clip
# path matches, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy)) +
  geom_point() +
  facet_wrap(~class) +
  theme_gray() +
  theme(strip.text = element_text(hjust = 0, face = "bold"))

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
