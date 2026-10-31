# The plot test/golden/theme_family_lato_geom_text.svg draws, drawn by ggplot2 itself through
# svglite in the fonts test/test_helper.exs registers under "Lato": the independent check on that
# golden whenever it changes. The suite never runs this; it needs R, ggplot2 and svglite, saved as
# the Docker image giggly-r:ggplot2-4.0.3-svglite, and the test fonts. From the repository's root:
#
#   docker run --rm -v "$PWD/test":/test:ro giggly-r:ggplot2-4.0.3-svglite \
#     Rscript /test/golden/theme_family_lato_geom_text.R > theme_family_lato_geom_text.svglite.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, once
# svglite's styles are written as vdiffr's copy of it writes them, a space after each semicolon
# (`sed -e 's/;\([^ ]\)/; \1/g'`).
#
# mtcars's cars by name at their weight and mileage, coloured by their cylinders, under Lato as the
# base family, which the layer's labels and the legend's keys take from the theme's `geom` element
# as its every text does, each measured in Lato.
#
# First checked with ggplot2 4.0.3 and svglite 2.2.2: every element pairs with svglite's and
# every number is within 0.02 points of it; 9 of the 51 labels' widths differ, by 0.02 points
# at most, as svglite's FreeType rounds a glyph's advance its own way (`Giggly.Font`). The one
# departure in order is test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

fonts <- list(Lato = list(
  plain = list(file = "/test/fonts/Lato-Regular.ttf", name = "Lato"),
  bold = list(file = "/test/fonts/Lato-Bold.ttf", name = "Lato")
))

mtcars$model <- rownames(mtcars)

plot <- ggplot(mtcars, aes(wt, mpg, label = model, colour = factor(cyl))) +
  geom_text() +
  theme_gray(base_family = "Lato")

file <- tempfile(fileext = ".svg")
svglite::svglite(file, width = 10, height = 8, user_fonts = fonts)
print(plot)
invisible(dev.off())
cat(readLines(file), sep = "\n")
