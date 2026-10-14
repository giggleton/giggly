defmodule Giggly.Scene.Polylines do
  @moduledoc false

  # Lines, each through its points in order, given as `{x, y}` in the cell's units, all of one
  # `stroke_width` (in points) and `color`, with square-cut ends: grid's `polylineGrob()`, which
  # ggplot2 draws an axis's ticks with, one two-point line per tick.

  @enforce_keys [:lines, :stroke_width, :color]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          lines: [[{float(), float()}]],
          stroke_width: float(),
          color: String.t()
        }
end
