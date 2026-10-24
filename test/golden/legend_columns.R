# The plot test/golden/legend_columns.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_columns.R > legend_columns.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Twenty-one points coloured by the letters a to u: a legend running down takes a column for each
# twenty keys, so one key more than twenty fills two columns a column at a time, eleven and ten,
# the keys' spacing between the first column's labels and the second column's keys.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and
# the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

df <- data.frame(x = 1:21, y = 1:21, key = letters[1:21])
plot <- ggplot(df, aes(x, y, colour = key)) +
  geom_point() +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
