# The plot test/golden/stack_text.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/stack_text.R > stack_text.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R does.
#
# position_stack's page's labels stacked over its areas, each label at the top of its band.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.R.

library(ggplot2)

set.seed(1)
series <- data.frame(
  time = c(rep(1, 4), rep(2, 4), rep(3, 4), rep(4, 4)),
  type = rep(c("a", "b", "c", "d"), 4),
  value = rpois(16, 10)
)
plot <- ggplot(series, aes(time, value, group = type)) +
  geom_area(aes(fill = type)) +
  geom_text(aes(label = type), position = "stack") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
