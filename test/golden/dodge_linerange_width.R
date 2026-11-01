# The plot test/golden/dodge_linerange_width.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/dodge_linerange_width.R > dodge_linerange_width.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R does.
#
# position_dodge's page's line ranges dodged within position_dodge(width = 0.9), each on its bar.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

d2 <- data.frame(x = c("a", "a", "b", "b"), y = 2:5, g = rep(1:2, 2), lo = 1:4, hi = 3:6)

plot <- ggplot(d2, aes(x, y, group = g)) +
  geom_col(position = "dodge", fill = "grey50", colour = "black") +
  geom_linerange(aes(ymin = lo, ymax = hi), position = position_dodge(width = 0.9)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
