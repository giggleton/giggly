defmodule Giggly.Scene.Rectangles do
  @moduledoc false

  # Rectangles placed and sized within their cell, each from `xmin` to `xmax` across it and from
  # `ymin` to `ymax` up it, in the cell's units, all filled with `fill`, each fill as opaque as its
  # `fill_opacity`, from 0 to 1, and bordered in `color`, `:none` for no border, with a border
  # `stroke_width` points wide, its corners square and its line ends cut square: grid's
  # `rectGrob()` as ggplot2's `GeomRect` draws it, one rectangle per bar, with `linejoin = "mitre"`
  # and `lineend = "butt"`, its fill carrying each bar's alpha as ggplot2's `fill_alpha()` gives it
  # and its border opaque.

  @enforce_keys [:xmin, :xmax, :ymin, :ymax, :fill, :fill_opacity, :color, :stroke_width]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          xmin: [float()],
          xmax: [float()],
          ymin: [float()],
          ymax: [float()],
          fill: String.t(),
          fill_opacity: [float()],
          color: String.t() | :none,
          stroke_width: float()
        }
end
