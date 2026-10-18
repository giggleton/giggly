# The plot test/golden/labs.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests draw
# their snapshots: the independent check on that golden whenever it changes. The suite never runs
# this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From the
# repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/labs.R > labs.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# ggplot2's ggtheme reference page's "The default theme" example: mtcars' fuel economy against
# weight, coloured by gears, with every label labs() sets: a title, subtitle, caption and tag, both
# axes' titles and the legend's, the gears read as a factor in both. First checked with ggplot2
# 4.0.3 and vdiffr 1.0.9: every element and clip path matches but svglite's around the whole
# drawing, and the one departure is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

mtcars2 <- within(mtcars, {
  vs <- factor(vs, labels = c("V-shaped", "Straight"))
  am <- factor(am, labels = c("Automatic", "Manual"))
  cyl  <- factor(cyl)
  gear <- factor(gear)
})

plot <- ggplot(mtcars2) +
  geom_point(aes(x = wt, y = mpg, colour = gear)) +
  labs(
    title = "Fuel economy declines as weight increases",
    subtitle = "(1973-74)",
    caption = "Data from the 1974 Motor Trend US magazine.",
    tag = "Figure 1",
    x = "Weight (1000 lbs)",
    y = "Fuel economy (mpg)",
    colour = "Gears"
  ) +
  theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
