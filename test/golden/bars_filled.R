# The plot test/golden/bars_filled.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/bars_filled.R > bars_filled.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Each cylinder count's cars by engine shape, each bar's pile filled to 1, as position_stack()'s
# reference page fills them.

library(ggplot2)
plot <- ggplot(mtcars, aes(factor(cyl), fill = factor(vs))) +
  geom_bar(position = "fill") + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
