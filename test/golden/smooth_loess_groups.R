# The plot test/golden/smooth_loess_groups.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/smooth_loess_groups.R > smooth_loess_groups.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes. Its loess is
# fitted as Giggly fits one, by test/golden/giggly_loess.R.
#
# A loess curve for each drive, each band before its own line.

source("/golden/giggly_loess.R")
plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_smooth(method = giggly_loess, formula = y ~ x) + theme_gray()
file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
