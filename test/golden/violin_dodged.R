# The plot test/golden/violin_dodged.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/violin_dodged.R > violin_dodged.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, `<line>`
# elements included.
#
# The reference page's violins filled by factor(vs): each cylinder count's violins dodged
# side by side, a group of one row left out, and a legend of polygon keys.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

plot <- ggplot(mtcars, aes(factor(cyl), mpg)) +
  geom_violin(aes(fill = factor(vs))) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
