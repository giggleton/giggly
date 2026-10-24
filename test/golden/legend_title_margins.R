# The plot test/golden/legend_title_margins.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/legend_title_margins.R > legend_title_margins.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# Six points coloured by the letters a to f, their legend below the panel: six keys running across,
# one more than a row holds, take two rows filled a column at a time; the title left of them has a
# margin of its own, 30 points above it, 6 right of it and 12 below, which replaces the keys'
# spacing, so it and its margins are taller than the two rows, which take half the rest above them
# and half below, and its text is moved down by half the difference of its margins.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches, and
# the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

df <- data.frame(x = 1:6, y = 1:6, key = letters[1:6])
plot <- ggplot(df, aes(x, y, colour = key)) +
  geom_point() +
  theme_gray() +
  theme(
    legend.position = "bottom",
    legend.title = element_text(margin = margin(t = 30, r = 6, b = 12))
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
