defmodule Scales do
  @moduledoc false

  # R's scales half of a plot's scales, the package that will leave this repository once
  # complete (design-log §4, the entry beginning "`scales`, a package of R's scales half"): breaks
  # (`Scales.Breaks`, `Scales.DateBreaks`, `Scales.MinorBreaks`), labels (`Scales.Labels`),
  # transformations (`Scales.Transform`), palettes (`Scales.Palette`), values
  # against a range's bounds (`Scales.Bounds`), the range of the data a scale trains on
  # (`Scales.DataRange`) and colour operations (`Scales.ColorOperations`). It works on plain
  # values and depends on nothing in Giggly; ggplot2's half, a scale's kind, its defaults, its
  # training and mapping, stays in `Giggly.Scale`.
  #
  # It lists `Color`, which `Scales.ColorOperations` converts colours with, and `NimbleOptions`,
  # which checks `Scales.Labels`'s options. It exports what Giggly's code calls; what a user calls
  # is the documented API (CLAUDE.md, Conventions).
  use Boundary,
    deps: [Color, NimbleOptions],
    exports: [Bounds, ColorOperations, DataRange, DateBreaks, Palette, Transform]
end
