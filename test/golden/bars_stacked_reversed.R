# The plot test/golden/bars_stacked_reversed.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/bars_stacked_reversed.R > bars_stacked_reversed.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Horizontal bars of each class's cars by drive train, the stack reversed so it reads in the
# legend's order along the bar, as geom_bar()'s reference page reverses it.

library(ggplot2)
plot <- ggplot(mpg, aes(y = class)) +
  geom_bar(aes(fill = drv), position = position_stack(reverse = TRUE)) +
  theme_gray() + theme(legend.position = "top")
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
