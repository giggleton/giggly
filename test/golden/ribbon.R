# The plot test/golden/ribbon.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/ribbon.R > ribbon.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# geom_ribbon()'s band around a line from ggplot2's reference page, over Lake Huron's levels
# from 1875 to 1904: a band from a foot below the level to a foot above, in R's grey70, with no
# outline, its polygon out along the upper edge and back along the lower, drawn under the line.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, the x axis drawn
# before the y as test/golden/point.R describes, and every clip path.

library(ggplot2)
huron <- data.frame(year = 1875:1904, level = c(580.38, 581.86, 580.97, 580.80, 579.79, 580.39,
  580.42, 580.82, 581.40, 581.32, 581.44, 581.68, 581.17, 580.53, 580.01, 579.91, 579.14, 579.16,
  579.55, 579.67, 578.44, 578.24, 579.10, 579.09, 579.35, 578.82, 579.32, 579.01, 579.00, 579.80))
plot <- ggplot(huron, aes(year)) +
  geom_ribbon(aes(ymin = level - 1, ymax = level + 1), fill = "grey70") +
  geom_line(aes(y = level)) +
  theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
