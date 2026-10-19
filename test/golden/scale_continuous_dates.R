# The plot test/golden/scale_continuous_dates.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_continuous_dates.R > scale_continuous_dates.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# economics's unemployment month by month under scale_x_continuous(): each date at its days since
# 1970-01-01, the axis marked and labelled as numbers, as R stores a date.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the one
# departure test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(economics, aes(date, unemploy)) +
  geom_line() +
  scale_x_continuous() +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
