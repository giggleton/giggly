# The plot test/golden/labels_log_turned.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/labels_log_turned.R > labels_log_turned.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# label_log()'s powers on an x axis whose text is turned 90 degrees and set bold: each power turned
# about its anchor as one box, and drawn plain, as plotmath draws whatever the face; and in a size
# legend, each key's label boxed as plotmath boxes it, left-aligned and centred. First checked
# with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but svglite's around
# the whole drawing, and the one departure is test/golden/point.R's, the x axis drawn before the
# y.

library(ggplot2)

points <- data.frame(x = c(1, 10, 100, 1000), y = c(1, 2, 3, 4))

plot <- ggplot(points, aes(x, y, size = x)) +
  geom_point() +
  scale_x_log10(labels = scales::label_log()) +
  scale_size_continuous(breaks = c(10, 100, 1000), labels = scales::label_log()) +
  theme_gray() +
  theme(axis.text.x = element_text(angle = 90, face = "bold"))

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
