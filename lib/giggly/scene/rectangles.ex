defmodule Giggly.Scene.Rectangles do
  @moduledoc false

  # Rectangles placed and sized within their cell, each from `xmin` to `xmax` across it and from
  # `ymin` to `ymax` up it, in the cell's units, either way round, as grid takes a rectangle given a
  # negative width or height, each filled with its `fill`, `#RRGGBB` or `:none`
  # for no fill, as opaque as its `fill_opacity`, from 0 to 1, and bordered in its `color`,
  # `#RRGGBB` or `:none` for no border, as opaque as its `color_opacity`, all with a border
  # `stroke_width` points wide, its corners square and its line ends cut square: grid's
  # `rectGrob()` as ggplot2's `GeomRect` draws it, one rectangle per bar or rectangle, with `linejoin = "mitre"`
  # and `lineend = "butt"`, its fill carrying each bar's alpha as ggplot2's `fill_alpha()` gives it
  # and its border its colour's own alpha alone.

  @enforce_keys [
    :xmin,
    :xmax,
    :ymin,
    :ymax,
    :fill,
    :fill_opacity,
    :color,
    :color_opacity,
    :stroke_width
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          xmin: [float()],
          xmax: [float()],
          ymin: [float()],
          ymax: [float()],
          fill: [String.t() | :none],
          fill_opacity: [float()],
          color: [String.t() | :none],
          color_opacity: [float()],
          stroke_width: float()
        }
end
