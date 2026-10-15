defmodule Giggly.Scene.Polylines do
  @moduledoc false

  # Lines, each through its points in order, given as `{x, y}` in the cell's units, all of one
  # `stroke_width` (in points) and `color`, with square-cut ends and never filled: grid's
  # `polylineGrob()`, which ggplot2 draws an axis's ticks and a panel's grid lines with, one line
  # per tick or grid line. `offsets` moves each point a number of points across and up from its
  # place, one `{across, up}` for each point, line by line, as grid adds a unit in points to one
  # in the viewport's own (`unit(x, "npc") + unit(d, "pt")`): a tick reaching out from a circle
  # whose size in points is known only when the scene is laid out. `:none` moves no point.

  @enforce_keys [:lines, :offsets, :stroke_width, :color]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          lines: [[{float(), float()}]],
          offsets: :none | [[{float(), float()}]],
          stroke_width: float(),
          color: String.t()
        }
end
