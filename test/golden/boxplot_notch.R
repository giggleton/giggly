# The plot test/golden/boxplot_notch.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/boxplot_notch.R > boxplot_notch.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, `<line>`
# elements included.
#
# The reference page's notched and varying-width boxes, together: mpg's highway mileage by class,
# each box as wide as the square root of its rows makes it beside the widest, dodged at its own
# width, and notched at its median, pinched in to half its width; ggplot2 also says "Notch went
# outside hinges", which a pure pipeline cannot.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(class, hwy)) +
  geom_boxplot(notch = TRUE, varwidth = TRUE) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
