# The plot test/golden/bar_line_types.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/bar_line_types.R > bar_line_types.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Two bars filled by group, bordered black, 1.5 mm wide and dotted, their legend's keys each its
# fill short of the key by 1.5 mm and bordered alike; a column annotation of eight bars, each
# bordered in one of R's seven line types or the dash pattern "3313", at the default width, the
# blank one's border not drawn; and a rectangle annotation in the same eight line types at widths
# 0.2, 1 and 2 mm, two of each, then 0.5; and a dashed rectangle with no border colour. Every
# border is dashed as svglite writes it, each length times the border's width in line-width units,
# or alone where the border is narrower than one, and written whether or not the border has a
# colour. First checked with ggplot2 4.0.3 and vdiffr
# 1.0.9: every element matches, in the same order, the x axis drawn before the y as
# test/golden/point.R describes, and every clip path.

library(ggplot2)

types <- c("blank", "solid", "dashed", "dotted", "dotdash", "longdash", "twodash", "3313")
data <- data.frame(x = c(1, 2), y = c(3, 2), g = c("p", "q"))
plot <- ggplot(data, aes(x, y, fill = g)) +
  geom_col(colour = "black", linewidth = 1.5, linetype = "dotted") +
  annotate("col", x = 3:10, y = 1, colour = "black", linetype = types) +
  annotate("rect", xmin = 3:10 - 0.45, xmax = 3:10 + 0.45, ymin = 2, ymax = 3,
    colour = "black", linetype = types, linewidth = c(0.2, 0.2, 1, 1, 2, 2, 0.5, 0.5)) +
  annotate("rect", xmin = 0.55, xmax = 2.45, ymin = 3.5, ymax = 4, linetype = "dashed") +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
