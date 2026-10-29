# The plot test/golden/segment_arrow_style.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/segment_arrow_style.R > segment_arrow_style.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# A head takes its line's whole style: two dashed segments 2 mm wide with open heads at their first
# ends, at grid's defaults (30 degrees, 0.25 in), dashed as their lines are; and two segments with
# mitred corners and round ends, their closed heads unfilled (`arrow.fill = NA`). First checked with
# ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x axis drawn before the y
# as in test/golden/point.svg.

library(ggplot2)

df <- data.frame(x = c(1, 2), y = c(1, 3), xend = c(2, 3), yend = c(2, 1))
plot <- ggplot(df, aes(x, y, xend = xend, yend = yend)) +
  geom_segment(linetype = "dashed", linewidth = 2, arrow = arrow(ends = "first")) +
  geom_segment(
    aes(y = y + 1, yend = yend + 1),
    linejoin = "mitre", lineend = "round", arrow = arrow(type = "closed"), arrow.fill = NA
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
