# The plot test/golden/theme_family_elements.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_family_elements.R > theme_family_elements.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, which leaves
# out each label's font-family: vdiffr writes `sans` for every family and measures each with
# Liberation Sans, as Giggly measures it, where Giggly names the family.
#
# mpg's highway mileage against engine size, coloured by drive train, in a panel per year, each
# text's family its own element's: the tick labels monospaced, the strips and the legend's title
# serif, and the legend's labels in a font named by its name, Lobster.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but the
# background's edge, which svglite writes as R's rounding error.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_point() +
  facet_wrap(~year) +
  theme_gray() +
  theme(
    axis.text = element_text(family = "mono"),
    strip.text = element_text(family = "serif"),
    legend.title = element_text(family = "serif"),
    legend.text = element_text(family = "Lobster")
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
