# The plot test/golden/labels_stacked_middle.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/labels_stacked_middle.R > labels_stacked_middle.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Columns stacked, one below zero piling down from it, each labelled in the middle of its part by
# stacking's vjust = 0.5, as position_stack()'s reference page labels them.

library(ggplot2)
df <- data.frame(
  x = rep(c("a", "b"), 2:3),
  y = c(1, 2, 1, 3, -1),
  grp = c("x", "y", "x", "y", "y")
)
plot <- ggplot(data = df, aes(x, y, group = grp)) +
  geom_col(aes(fill = grp)) +
  geom_hline(yintercept = 0) +
  geom_text(aes(label = grp), position = position_stack(vjust = 0.5)) + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
