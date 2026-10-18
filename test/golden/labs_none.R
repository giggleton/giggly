# The plot test/golden/labs_none.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/labs_none.R > labs_none.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# scale_continuous()'s reference page's "Removing axis titles" example: mpg's highway mileage
# against engine size, both axes' titles removed with labs(x = NULL, y = NULL), and the room they
# took with them. First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path
# matches but svglite's around the whole drawing, and the one departure is test/golden/point.R's,
# the x axis drawn before the y.

library(ggplot2)

p1 <- ggplot(mpg, aes(displ, hwy)) +
  geom_point()
plot <- p1 + labs(x = NULL, y = NULL) + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
