# The plot test/golden/date_line.svg draws, drawn by ggplot2 itself, as ggplot2's own visual tests
# draw their snapshots: the independent check on that golden whenever it changes. The suite never
# runs this; it needs R, ggplot2 and vdiffr, saved as the Docker image giggly-r:ggplot2-4.0.3. From
# the repository's root:
#
#   docker run --rm -v "$PWD/test/golden":/golden:ro giggly-r:ggplot2-4.0.3 \
#     Rscript /golden/date_line.R > date_line.ggplot2.svg
#
# and compare the two drawings element by element, as test/golden/line_missing.R does.
#
# The first example on ggplot2's geom_path reference page: economics's unemployment month by month
# from 1967 to 2015, a line through 574 rows in order of date, the x axis a date scale whose breaks
# are R's pretty() for dates, 1970 to 2010 by ten years, labelled by year, with minor grid lines
# midway between them. First checked with ggplot2 4.0.3 and vdiffr 1.0.9: every element and clip
# path matches but svglite's around the whole drawing, and the one departure is
# test/golden/point.R's, the x axis drawn before the y.

library(ggplot2)

plot <- ggplot(economics, aes(date, unemploy)) + geom_line() + theme_gray()

file <- tempfile(fileext = ".svg")
vdiffr::write_svg(plot, file)
cat(readLines(file), sep = "\n")
