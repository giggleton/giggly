# The plot test/golden/area_identity.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/area_identity.R > area_identity.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Two groups' areas drawn where they are, overlapping at an alpha of 0.4, each bordered whole,
# 0.8 mm wide, the border taking no alpha, the keys bordered as the areas are.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn
# before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
data <- data.frame(g = rep(c("a", "b"), each = 5), x = rep(1:5, 2), y = c(1, 3, 2, 4, 3, 2, 1, 3, 2, 4))
plot <- ggplot(data, aes(x, y, fill = g)) +
  geom_area(position = "identity", alpha = 0.4, colour = "black", linewidth = 0.8,
    outline.type = "full") +
  theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
