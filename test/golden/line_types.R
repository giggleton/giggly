# The plot test/golden/line_types.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/line_types.R > line_types.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Each of R's seven line types by name, from the bottom up, and the dash pattern "3313", one path
# annotation each at R's default width, 0.5 mm, where each dash is its length times the line's
# width in line-width units (1.42); a dashed line 0.2 mm wide, narrower than one unit, whose
# dashes are their lengths alone; and a colour legend's two lines, long-dashed and 1 mm wide, their
# keys dashed alike. The blank line draws nothing. First checked with ggplot2 4.0.3 and vdiffr
# 1.0.9: every element matches, in the same order, the x axis drawn before the y as
# test/golden/point.R describes, and every clip path.

library(ggplot2)

types <- c("blank", "solid", "dashed", "dotted", "dotdash", "longdash", "twodash", "3313")
data <- data.frame(x = c(0, 10, 0, 10), y = c(10, 10, 11, 11), g = c("p", "p", "q", "q"))
plot <- ggplot(data, aes(x, y, colour = g)) +
  geom_line(linetype = "longdash", linewidth = 1)
for (index in seq_along(types)) {
  plot <- plot + annotate("path", x = c(0, 10), y = index, linetype = types[index])
}
plot <- plot +
  annotate("path", x = c(0, 10), y = 9, linetype = "dashed", linewidth = 0.2) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
