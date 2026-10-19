# The plot test/golden/guide_legend_reverse.svg draws, drawn by ggplot2 itself, as ggplot2's own
# visual tests draw their snapshots: the independent check on that golden whenever it changes. The
# suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/guide_legend_reverse.R > guide_legend_reverse.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# guide_legend()'s reference page's reversed legend: twenty points coloured by the letters a to t,
# the keys from t at the top down to a.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9.

library(ggplot2)

df <- data.frame(x = 1:20, y = 1:20, color = letters[1:20])
plot <- ggplot(df, aes(x, y)) +
  geom_point(aes(colour = color)) +
  guides(col = guide_legend(reverse = TRUE)) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
