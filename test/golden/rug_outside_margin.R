# The plot test/golden/rug_outside_margin.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/rug_outside_margin.R > rug_outside_margin.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# The example on ggplot2's geom_rug reference page moving the rug outside along the top and the
# right: a centimetre of plot margin on every side leaves the lines room past the panel's edge.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.svg.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg)) +
  geom_point() +
  geom_rug(outside = TRUE, sides = "tr") +
  coord_cartesian(clip = "off") +
  theme_gray() +
  theme(plot.margin = margin_auto(1, unit = "cm"))

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
