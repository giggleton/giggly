# The plot test/golden/line_alpha.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/line_alpha.R > line_alpha.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# A line whose alpha changes along it: four rows put in order of x, each with its own alpha, so
# ggplot2 draws the line as a segment from each row to the next, each as opaque as the row it
# starts from, and the legend that reads alpha back, titled z, a key for each of 1 to 4, each key
# a segment across its middle, as draw_key_path() draws it. First checked with ggplot2 4.0.3 and
# vdiffr 1.0.9: every element and clip path matches but svglite's around the whole drawing, and
# the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

df <- data.frame(x = c(1, 3, 2, 4), y = c(1, 2, 4, 3), z = c(1, 2, 3, 4))
plot <- ggplot(df, aes(x, y, alpha = z)) + geom_line() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
