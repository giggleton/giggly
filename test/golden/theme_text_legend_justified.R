# The plot test/golden/theme_text_legend_justified.svg draws, drawn by ggplot2 itself, as ggplot2's
# own visual tests draw their snapshots: the independent check on that golden whenever it changes.
# The suite never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image
# giggly-r:ggplot2-4.0.3. From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_text_legend_justified.R > theme_text_legend_justified.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# mpg's highway mileage against engine size by class, the legend's labels right-aligned in their
# column and its italic title, wider than the keys and labels, right-aligned too, so the keys sit
# at the legend's right.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = class)) +
  geom_point() +
  labs(colour = "Vehicle class, as the EPA lists it") +
  theme_gray() +
  theme(
    legend.text = element_text(hjust = 1),
    legend.title = element_text(hjust = 1, face = "italic")
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
