# The plot test/golden/scale_date_width.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/scale_date_width.R > scale_date_width.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# The scale_date reference page's `base`, its last 30 days ending on 2026-10-19 rather than on
# the day it runs, and its prices R's runif(30) after set.seed(1), with a break every week laid
# from the Monday before the axis's start, each labelled by its day of the month, and a minor grid
# line every day.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the one
# departure test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

last_month <- as.Date("2026-10-19") - 0:29
set.seed(1)
df <- data.frame(date = last_month, price = runif(30))
plot <- ggplot(df, aes(date, price)) +
  geom_line() +
  scale_x_date(date_breaks = "1 week", date_labels = "%d", date_minor_breaks = "1 day") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
