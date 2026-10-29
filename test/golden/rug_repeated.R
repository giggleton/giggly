# The plot test/golden/rug_repeated.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/rug_repeated.R > rug_repeated.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# Translucent rugs over rows repeated in every column: along the bottom and left a repeated row is
# drawn once, as ggplot2 joins the two axes' rows with vctrs::vec_set_union(), and along the top
# alone every time, so its lines darken where they pile up; a row missing its x comes last along
# the left, after the rows with an x.
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, the x
# axis drawn before the y as in test/golden/point.svg.

library(ggplot2)

df <- data.frame(x = c(1, NA, 1, 2, 1), y = c(5, 7, 5, 6, 5))
plot <- ggplot(df, aes(x, y)) +
  geom_rug(alpha = 0.3, linewidth = 2) +
  geom_rug(sides = "t", alpha = 0.3, linewidth = 2) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
