# The plot test/golden/theme_root_text.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_root_text.R > theme_root_text.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# The root text removed: every text goes, the title and caption with their rows, but what a
# setting gives and the legend's title and labels, which ggplot2's legend draws by laying a text
# of its own over the theme's root, replacing the removal, so they keep theme_gray()'s look. The y
# axis's labels are red at 10 points, with theme_gray()'s margin; the subtitle, red, takes grid's
# 12-point font and line spacing, since nothing above it gives a size or a line height.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches once positions are
# rounded to two decimals (svglite writes the background's edge as R's rounding error), every clip
# path matches, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_point() +
  labs(title = "Title", subtitle = "A subtitle\nover two lines", caption = "Caption") +
  theme_gray() +
  theme(
    text = element_blank(),
    plot.subtitle = element_text(colour = "red"),
    axis.text.y = element_text(colour = "red", size = 10)
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
