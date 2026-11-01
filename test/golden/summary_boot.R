# The plot test/golden/summary_boot.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2, vdiffr and Hmisc, saved as the Docker image
# giggly-r:ggplot2-4.0.3-hmisc (giggly-r:ggplot2-4.0.3 with r-cran-hmisc installed). From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3-hmisc \
#     Rscript /golden/summary_boot.R > summary_boot.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R does.
#
# The reference page's `stat_summary(fun.data = "mean_cl_boot", colour = "red", linewidth = 2,
# size = 3)`: each cylinder count's mean and its 95% bootstrap interval.
#
# Hmisc resamples with R's random numbers, which Giggly does not reproduce, so R draws Giggly's
# own ends instead: `lower` and `upper` are the ends Giggly's mean_cl_boot gives at its default
# seed, 0, for 4, 6 and 8 cylinders, and the summary function hands each position its own, found
# by how many values it holds (11, 7 and 14), beside R's mean. Everything but the ends is
# ggplot2's.
# First checked with ggplot2 4.0.3, vdiffr 1.0.9 and Hmisc 5.3.0: every element and clip path
# matches, the x axis drawn before the y as in test/golden/point.R.

library(ggplot2)

lower <- c("11" = 24.31772727272727, "7" = 18.699999999999996, "14" = 13.821250000000001)
upper <- c("11" = 29.329090909090908, "7" = 20.72857142857143, "14" = 16.29303571428571)

gigglys_ends <- function(x) {
  count <- as.character(length(x))
  data.frame(y = mean(x), ymin = lower[[count]], ymax = upper[[count]])
}

plot <- ggplot(mtcars, aes(cyl, mpg)) +
  geom_point() +
  stat_summary(fun.data = gigglys_ends, colour = "red", linewidth = 2, size = 3) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
