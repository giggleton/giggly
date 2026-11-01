# The plot test/golden/summary_line_flipped.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/summary_line_flipped.R > summary_line_flipped.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R does.
#
# Means joined by a line for each engine shape, its group, across the panel: y alone discrete, so
# the summary runs along y and the line takes its order from the stat's flipped_aes.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

plot <- ggplot(mtcars, aes(mpg, factor(cyl), colour = factor(vs), group = vs)) +
  geom_point() +
  stat_summary(fun = mean, geom = "line") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
