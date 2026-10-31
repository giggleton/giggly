# The plot test/golden/reference_line_keys.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/reference_line_keys.R > reference_line_keys.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Both reference lines in one legend: each key a horizontal line across its middle, as a path's,
# and a vertical one from its bottom to its top, `draw_key_vline()`, in the key's colour and line
# type; the lines' ends square.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

marks <- data.frame(wt = c(2.5, 4.5), mpg = c(15, 30), kind = c("low", "high"))
plot <- ggplot(mtcars, aes(wt, mpg)) + geom_point() +
  geom_vline(aes(xintercept = wt, colour = kind, linetype = kind), marks, lineend = "square") +
  geom_hline(aes(yintercept = mpg, colour = kind, linetype = kind), marks, lineend = "square") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
