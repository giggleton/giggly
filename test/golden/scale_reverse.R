# The plot test/golden/scale_reverse.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_reverse.R > scale_reverse.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# The lims reference page's reversed scale: mtcars' mileage against weight with xlim(20, 15), the
# larger limit first, so the x axis runs from 20 down to 15 and the cars outside it are missing.

library(ggplot2)

plot <- ggplot(mtcars, aes(mpg, wt)) +
  geom_point() +
  xlim(20, 15) +
  theme_gray()

file <- tempfile(fileext = ".svg")
suppressWarnings(vdiffr::write_svg(plot, file))
cat(readLines(file), sep = "\n")
