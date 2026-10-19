# The plot test/golden/legends_reverse_unmerged.svg draws, drawn by ggplot2 itself, as ggplot2's
# own visual tests draw their snapshots: the independent check on that golden whenever it changes.
# The suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legends_reverse_unmerged.R > legends_reverse_unmerged.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's classes counted, each bar outlined and filled by drive train, the colour's legend reversed:
# its labels no longer read as the fill's, so the two are drawn apart rather than merged. ggplot2
# orders legends by a hash of their contents, so `order` puts the colour's first, as Giggly orders
# them by aesthetic name.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9.

library(ggplot2)

plot <- ggplot(mpg, aes(class, fill = drv, colour = drv)) +
  geom_bar() +
  guides(
    colour = guide_legend(reverse = TRUE, order = 1),
    fill = guide_legend(order = 2)
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
