# The plot test/golden/errorbar_flipped.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/errorbar_flipped.R > errorbar_flipped.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R does.
#
# Error bars turned by mapping xmin and xmax, so they run across the panel, their whiskers 0.9 of
# the discrete y axis's spacing.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

df <- data.frame(
  trt = factor(c(1, 1, 2, 2)),
  resp = c(1, 5, 3, 4),
  group = factor(c(1, 2, 1, 2)),
  upper = c(1.1, 5.3, 3.3, 4.2),
  lower = c(0.8, 4.6, 2.4, 3.6)
)

plot <- ggplot(df, aes(resp, trt, colour = group)) +
  geom_errorbar(aes(xmin = lower, xmax = upper)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
