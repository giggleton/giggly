# The plot test/golden/facet_grid_labeller_wrap.svg draws, drawn by ggplot2 itself, as ggplot2's
# own visual tests draw their snapshots: the independent check on that golden whenever it changes.
# The suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/facet_grid_labeller_wrap.R > facet_grid_labeller_wrap.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Four points in a grid of panels by a conservation status, across and down, each strip's label
# wrapped under 10 characters: three labels break into two lines, stacked down in the strips above
# and leftward in the strips to the right, and "Domesticated", one line, is centred in a strip as
# deep as its row's two-line ones.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in order, and every
# clip path matches.

library(ggplot2)

status <- c("Conservation Dependent", "Least concern", "Near Threatened", "Domesticated")
data <- data.frame(x = 1:4, y = 1:4, g = status, h = status)
plot <- ggplot(data, aes(x, y)) +
  geom_point() +
  facet_grid(h ~ g, labeller = label_wrap_gen(10)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
