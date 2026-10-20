defmodule Giggly.Scene.Rectangles do
  @moduledoc false

  # Rectangles placed and sized within their cell, each from `xmin` to `xmax` across it and from
  # `ymin` to `ymax` up it, in the cell's units, either way round, as grid takes a rectangle given a
  # negative width or height, each filled with its `fill`, `#RRGGBB` or `:none`
  # for no fill, as opaque as its `fill_opacity`, from 0 to 1, and bordered in its `color`,
  # `#RRGGBB` or `:none` for no border, as opaque as its `color_opacity`, all with a border
  # `stroke_width` points wide, its corners and ends drawn as `Giggly.Scene.Polylines` draws a
  # line's: grid's `rectGrob()`. ggplot2's `GeomRect` draws one per bar or rectangle, with
  # `linejoin = "mitre"` and `lineend = "butt"`, its fill carrying each bar's alpha as ggplot2's
  # `fill_alpha()` gives it and its border its colour's own alpha alone; R's graphics engine draws a
  # point's open and filled squares, with grid's round corners and ends. `offsets` moves each
  # rectangle's corners a number of points across and up from their places, one
  # `{{across, up}, {across, up}}` for each rectangle, the first moving its `xmin` and `ymin` and
  # the second its `xmax` and `ymax`, as `Giggly.Scene.Polylines` moves a line's points: a point's
  # square is drawn round its place at a size in points. `:none` moves none. `dashes` dashes every
  # border as `Giggly.Scene.Polylines` dashes a line.

  @enforce_keys [
    :xmin,
    :xmax,
    :ymin,
    :ymax,
    :offsets,
    :fill,
    :fill_opacity,
    :color,
    :color_opacity,
    :stroke_width,
    :dashes,
    :line_end,
    :line_join,
    :mitre_limit
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          xmin: [float()],
          xmax: [float()],
          ymin: [float()],
          ymax: [float()],
          offsets: :none | [{{float(), float()}, {float(), float()}}],
          fill: [String.t() | :none],
          fill_opacity: [float()],
          color: [String.t() | :none],
          color_opacity: [float()],
          stroke_width: float(),
          dashes: Giggly.Scene.Polylines.dashes(),
          line_end: Giggly.Scene.Polylines.line_end(),
          line_join: Giggly.Scene.Polylines.line_join(),
          mitre_limit: float()
        }
end
