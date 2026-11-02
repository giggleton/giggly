# The plot test/golden/violin_quantiles_styled.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/violin_quantiles_styled.R > violin_quantiles_styled.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, `<line>`
# elements included.
#
# Quantile lines of their own colour, line type and width, faded by the violins' alpha, which
# leaves their borders alone; the lowest quantile's line runs left, right and left again, as it
# begins the outline.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mtcars, aes(factor(cyl), mpg)) +
  geom_violin(
    alpha = 0.5, quantiles = c(0, 0.5, 1), quantile.colour = "red",
    quantile.linetype = "dashed", quantile.linewidth = 1
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
