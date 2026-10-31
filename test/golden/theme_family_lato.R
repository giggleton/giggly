# The plot test/golden/theme_family_lato.svg draws, drawn by ggplot2 itself through svglite in the
# fonts test/test_helper.exs registers under "Lato": the independent check on that golden whenever
# it changes. The suite never runs this; it needs R, ggplot2 and svglite, saved as the Docker image
# giggly-r:ggplot2-4.0.3-svglite, and the test fonts. From the repository's root:
#
#   docker run --rm -v "$PWD/test":/test:ro giggly-r:ggplot2-4.0.3-svglite \
#     Rscript /test/golden/theme_family_lato.R > theme_family_lato.svglite.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, once
# svglite's styles are written as vdiffr's copy of it writes them, a space after each semicolon
# (`sed -e 's/;\([^ ]\)/; \1/g'`).
#
# mpg's highway mileage against engine size coloured by class, titled and subtitled, under Lato as
# the base family, its title in Lato Bold: every axis label and title, the legend's title and
# labels and the plot's titles measured in the face of Lato they are drawn in.
#
# First checked with ggplot2 4.0.3 and svglite 2.2.2: every element pairs with svglite's, every
# label as wide as svglite measures it, and every number within 0.04 points of svglite's; the
# one departure in order is test/golden/point.R's, the x axis drawn before the y. The gaps are
# in the heights: svglite's FreeType sizes Lato its own way, so a line's height above and below
# its baseline can land a pixel at 10,000 dots per inch, 0.0072 points, from Giggly's
# (`Giggly.Font`), and the title's and subtitle's four stack above the panel.

library(ggplot2)

fonts <- list(Lato = list(
  plain = list(file = "/test/fonts/Lato-Regular.ttf", name = "Lato"),
  bold = list(file = "/test/fonts/Lato-Bold.ttf", name = "Lato")
))

plot <- ggplot(mpg, aes(displ, hwy, colour = class)) +
  geom_point() +
  labs(
    title = "Fuel economy declines as engine size increases",
    subtitle = "Two seaters are the exception"
  ) +
  theme_gray(base_family = "Lato") +
  theme(plot.title = element_text(face = "bold"))

file <- tempfile(fileext = ".svg")
svglite::svglite(file, width = 10, height = 8, user_fonts = fonts)
print(plot)
invisible(dev.off())
cat(readLines(file), sep = "\n")
