defmodule Giggly.Scene.Polygons do
  @moduledoc false

  # Filled shapes, each closed round its outline, the points in order, given as `{x, y}` in the
  # cell's units, all with a border `stroke_width` points wide, each bordered in its `color` and
  # filled with its `fill`, `#RRGGBB` or `:none` for none, as opaque as its `color_opacity` and
  # `fill_opacity`, from 0 to 1, their borders' corners and ends drawn and dashed as
  # `Giggly.Scene.Polylines` draws and dashes a line: grid's `polygonGrob()`, which ggplot2 draws a
  # panel's background with when it is not a rectangle, with grid's round corners and ends, and a
  # box plot's box, with `linejoin = "mitre"` and `lineend = "butt"`, and R's graphics engine a
  # point's triangles, diamonds and filled square, round. `offsets` moves each point a number of
  # points across and up from its place, one `{across, up}` for each point, outline by outline, as
  # `Giggly.Scene.Polylines` moves a line's: a point's shape is drawn round its place at a size in
  # points. `:none` moves no point.

  @enforce_keys [
    :outlines,
    :offsets,
    :stroke_width,
    :color,
    :color_opacity,
    :fill,
    :fill_opacity,
    :dashes,
    :line_end,
    :line_join,
    :mitre_limit
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          outlines: [[{float(), float()}]],
          offsets: :none | [[{float(), float()}]],
          stroke_width: float(),
          color: [String.t() | :none],
          color_opacity: [float()],
          fill: [String.t() | :none],
          fill_opacity: [float()],
          dashes: Giggly.Scene.Polylines.dashes(),
          line_end: Giggly.Scene.Polylines.line_end(),
          line_join: Giggly.Scene.Polylines.line_join(),
          mitre_limit: float()
        }
end
