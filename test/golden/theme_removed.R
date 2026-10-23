# The plot test/golden/theme_removed.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_removed.R > theme_removed.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Removals across a faceted plot with a legend and every label: the tick labels, but the x axis's,
# which a setting gives and so skips its removed parent, drawn red at the root text's size, not
# axis.text's share of it; the x axis's ticks, so its labels move up to the panel, and its title;
# the minor grid lines; the strips' text, which takes the whole strip and its row with it; the
# legend's title and its keys' backgrounds; and the plot's subtitle and tag, each taking its room.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and the
# one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_point() +
  facet_wrap(~year) +
  labs(title = "Title", subtitle = "Subtitle", caption = "Caption", tag = "A") +
  theme_gray() +
  theme(
    axis.text = element_blank(),
    axis.text.x = element_text(colour = "red"),
    axis.ticks.x = element_blank(),
    axis.title.x = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_blank(),
    legend.title = element_blank(),
    legend.key = element_blank(),
    plot.subtitle = element_blank(),
    plot.tag = element_blank()
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
