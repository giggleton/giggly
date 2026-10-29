defmodule Scales do
  @moduledoc """
  R's scales package for Elixir: the pieces a chart's scales are built from, as plain functions
  of values, for any charting tool. Each gives the answer R's scales 1.4.0 gives, to the last
  digit; where one departs from R, its documentation says how and why.

  ## The families

  Each module holds one of R's families, and each function is R's name less the family's prefix,
  its documentation naming R's: R's `breaks_extended()` is `Scales.Breaks.extended/2`.

  | Module | What it holds | R's family |
  | --- | --- | --- |
  | `Scales.Breaks` | where an axis's breaks go | `breaks_*` |
  | `Scales.MinorBreaks` | minor breaks between them | `regular_minor_breaks()`, `minor_breaks_*` |
  | `Scales.Labels` | labels for breaks | `label_*`, `cut_*` |
  | `Scales.Transform` | transformations, with their breaks and labels | `transform_*` |
  | `Scales.Palette` | palettes, from a place or a count to an aesthetic's value | `pal_*`, `palette_*`, `as_*_pal()` |
  | `Scales.Bounds` | rescaling, zero width, values outside a range | `rescale*`, `oob_*`, `zero_range()` |
  | `Scales.DataRange` | the range of the data a scale has seen | `train_*` |
  | `Scales.ColorOperations` | colours as written and as R's palettes make them | `col_*` |

  ## Conventions

    * A range is `{low, high}`.
    * `nil` is R's `NA`, a missing value, and R's `NaN` where a function would give one;
      `:infinity` and `:neg_infinity` are R's infinities.
    * A colour is uppercase `#RRGGBB`, or `#RRGGBBAA` with an alpha of its own; `:none` is no
      colour, R's `NA`.
    * A function takes a list where R takes a vector, and its options as a keyword list of R's
      arguments, spelled out, checked as it is called: a bad one raises.
    * Elixir's words stand where R's differ: `:time` is a time of day (R's `hms`), `{:datetime,
      ...}` a date-time (R's `POSIXct`), and grey is `gray`.

  ## An example

  The steps a charting tool takes for a continuous colour scale: train a range on the data, find
  its breaks, some of which may fall outside it, label them, and map each value through a
  palette by its place in the range.

      iex> values = [12.0, 31.5, 18.25, nil]
      iex> range = Scales.DataRange.train_continuous(:none, values)
      {12.0, 31.5}
      iex> breaks = Scales.Breaks.extended(range)
      [10.0, 15.0, 20.0, 25.0, 30.0]
      iex> Scales.Labels.comma(breaks, suffix: " km")
      ["10 km", "15 km", "20 km", "25 km", "30 km"]
      iex> places = Scales.Bounds.rescale(values, range, {0, 1})
      [0.0, 1.0, 0.32051282051282054, nil]
      iex> Scales.Palette.continuous({:gradient, ["#132B43", "#56B1F7"]}, places)
      ["#132B43", "#56B1F7", "#275278", nil]
  """

  # R's scales half of a plot's scales, the package that will leave this repository once
  # complete (design-log §4, the entry beginning "`scales`, a package of R's scales half"). It
  # works on plain values and depends on nothing in Giggly; ggplot2's half, a scale's kind, its
  # defaults, its training and mapping, stays in `Giggly.Scale`.
  #
  # It lists `Color`, which `Scales.ColorOperations` converts colours with, and `NimbleOptions`,
  # which checks its functions' options. It exports what Giggly's code calls; what a user calls
  # is the documented API (CLAUDE.md, Conventions).
  use Boundary,
    deps: [Color, NimbleOptions],
    exports: [Bounds, ColorOperations, DataRange, Palette, Transform]
end
