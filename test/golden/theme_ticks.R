# The plot test/golden/theme_ticks.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_ticks.R > theme_ticks.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes.
#
# ggplot2's theme reference page's "The length and direction of ticks" example, on mtcars' fuel
# economy against weight with a title, a caption and a tag: the y axis's ticks 0.25 cm long, the x
# axis's -0.25 cm, turned into the panel, taking no room, its labels 0.3 cm below the panel.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches but
# svglite's around the whole drawing, and the one departure is test/golden/point.R's, the x axis
# drawn before the y.

library(ggplot2)

plot <- ggplot(mtcars, aes(wt, mpg)) +
  geom_point() +
  labs(title = "Fuel economy declines as weight increases", caption = "A caption", tag = "A") +
  theme_gray() +
  theme(
    axis.ticks.length.y = unit(.25, "cm"),
    axis.ticks.length.x = unit(-.25, "cm"),
    axis.text.x = element_text(margin = margin(t = .3, unit = "cm"))
  )

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
