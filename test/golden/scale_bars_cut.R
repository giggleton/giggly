# The plot test/golden/scale_bars_cut.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_bars_cut.R > scale_bars_cut.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Counted bars under a y scale from 0 to 50 with no breaks: the suv bar, 62 rows, reaches past the
# limit once it is placed, so it is missing and not drawn, and the y axis, with no breaks, draws
# nothing and takes no room. The x scale's limits drop the rows outside them before counting.

library(ggplot2)

plot <- ggplot(mpg, aes(class)) +
  geom_bar() +
  scale_y_continuous(limits = c(0, 50), breaks = NULL) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
