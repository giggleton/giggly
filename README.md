# Giggly

A grammar of graphics for Elixir, after R's [ggplot2](https://ggplot2.tidyverse.org/): a plot maps
a table's columns to aesthetics and is built up from layers (each a geom, a stat and a position),
scales, a facet and a coordinate system, then drawn as SVG, for Phoenix LiveView, Livebook or a
file. There is no JavaScript to run: the SVG is the plot.

```elixir
svg =
  Giggly.Datasets.mtcars()
  |> Giggly.Plot.new(%{x: :wt, y: :mpg, color: :cyl})
  |> Giggly.Plot.geom_point()
  |> Giggly.Plot.labs(x: "Weight (1000 lb)", y: "Miles per gallon")
  |> Giggly.to_svg()

File.write!("mtcars.svg", svg)
```

A plot is a value: `Giggly.Plot` describes it and runs nothing, and the functions in `Giggly` run
it, `to_svg/2` to draw it and `layer_data/2` to show the table a layer computes. If you know
ggplot2, the names will be familiar: `geom_point()`, `scale_color_viridis_c()`, `facet_wrap()`,
`coord_radial()` and the rest are functions of `Giggly.Plot`.

## Installation

```elixir
def deps do
  [{:giggly, "~> 0.1"}]
end
```

Text is measured with a table of Liberation Sans's glyphs, as ggplot2's own test drawings are.
To measure and draw text in the fonts you name, add [Pica](https://hex.pm/packages/pica) too; the
[Fonts](guides/fonts.md) guide says how.

## Documentation

The `Giggly.Plot` documentation describes a plot and every layer, scale, facet, coordinate system
and theme function; the `Giggly` documentation, running one. Guides:

- [Fonts](guides/fonts.md): naming the fonts a plot's text is drawn in, and measuring and drawing
  them with Pica.

## Notebooks

The repository's [`notebooks/`](https://github.com/giggleton/giggly/tree/main/notebooks) holds a
Livebook notebook for every page of ggplot2's function reference, each following its page example
by example and drawing each one Giggly can draw so far. Start with `notebooks/index.livemd`, which
follows ggplot2's reference index and links every notebook.

## Licence

MIT; see [LICENSE](LICENSE). The datasets and glyph tables Giggly copies from R packages are
listed with their licences and sources in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
