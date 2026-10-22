# The plot test/golden/boxplot_parts.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/boxplot_parts.R > boxplot_parts.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, `<line>`
# elements included.
#
# Each part of a box in a look of its own, over two small groups: staples half the box's width
# across the whiskers' ends in blue, red whiskers, a median 2 mm wide, a dashed border, open
# outliers in dark green, and a legend of the fills whose keys draw every part's look.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

data <- data.frame(
  g = c(rep("a", 6), rep("b", 5)),
  y = c(1, 2, 3, 4, 5, 20, 2, 3, 3, 4, 9)
)

plot <- ggplot(data, aes(g, y, fill = g)) +
  geom_boxplot(
    staplewidth = 0.5,
    whisker.colour = "red",
    median.linewidth = 2,
    box.linetype = "dashed",
    staple.colour = "blue",
    outlier.shape = 1,
    outlier.colour = "darkgreen"
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
