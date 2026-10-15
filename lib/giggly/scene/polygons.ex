defmodule Giggly.Scene.Polygons do
  @moduledoc false

  # Filled shapes, each closed round its outline, the points in order, given as `{x, y}` in the
  # cell's units, all filled with `fill` and bordered in `color`, `:none` for no border, with a
  # border `stroke_width` points wide: grid's `polygonGrob()`, which ggplot2 draws a panel's
  # background with when it is not a rectangle.

  @enforce_keys [:outlines, :fill, :color, :stroke_width]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          outlines: [[{float(), float()}]],
          fill: String.t(),
          color: String.t() | :none,
          stroke_width: float()
        }
end
