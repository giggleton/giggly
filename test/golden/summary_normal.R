# The plot test/golden/summary_normal.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2, vdiffr and Hmisc, saved as the Docker image
# giggly-r:ggplot2-4.0.3-hmisc (giggly-r:ggplot2-4.0.3 with r-cran-hmisc installed). From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-hmisc \
#     Rscript /golden/summary_normal.R > summary_normal.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R does.
#
# The reference page's first summary, its point ranges at Hmisc's mean_cl_normal in place of
# mean_se: each cylinder count's mean and its 95% confidence interval from the t distribution.
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and Hmisc 5.3.0: every element and clip path
# matches, the x axis drawn before the y as in test/golden/point.R.

library(ggplot2)

plot <- ggplot(mtcars, aes(cyl, mpg)) +
  geom_point() +
  stat_summary(fun.data = "mean_cl_normal", colour = "red", linewidth = 2, size = 3) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
