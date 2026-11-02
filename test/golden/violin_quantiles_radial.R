# The plot test/golden/violin_quantiles_radial.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/violin_quantiles_radial.R > violin_quantiles_radial.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, `<line>`
# elements included.
#
# Quantile lines in radial coordinates, each munched to follow the panel's curves, as GeomPath
# munches it.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element matches, in R's order, and
# every clip path but svglite's around the whole drawing.

library(ggplot2)

plot <- ggplot(mtcars, aes(factor(cyl), mpg)) +
  geom_violin(quantile.linetype = 1) +
  coord_radial() +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
