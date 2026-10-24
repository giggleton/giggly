# The plot test/golden/theme_family_void.svg draws, drawn by ggplot2 itself, as ggplot2's own visual
# tests draw their snapshots: the independent check on that golden whenever it changes. The suite
# never runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3.
# From the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/theme_family_void.R > theme_family_void.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/point.R describes, which leaves
# out each label's font-family: vdiffr writes `sans` for every family and measures each with
# Liberation Sans, as Giggly measures it, where Giggly names the family.
#
# test/golden/theme_family_base_header.R's plot under theme_void(), whose families reach the
# texts it draws as theme_gray()'s do: the strips, the legend and the plot's titles.
#
# First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip path matches.

library(ggplot2)

plot <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
  geom_point() +
  facet_wrap(~year) +
  labs(
    title = "Fuel economy declines as engine size increases",
    subtitle = "Two seaters are the exception",
    caption = "Data from fueleconomy.gov",
    tag = "A"
  ) +
  theme_void(base_family = "serif", header_family = "mono")

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
