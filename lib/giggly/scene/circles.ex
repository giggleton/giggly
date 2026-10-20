defmodule Giggly.Scene.Circles do
  @moduledoc false

  # Circles, one at each `x` and `y` in the cell's units, each of its own `radius` in points, all
  # with an outline `stroke_width` points wide, each outlined in its `color` and filled with its
  # `fill`, `#RRGGBB` or `:none` for none, as opaque as its `color_opacity` and `fill_opacity`,
  # from 0 to 1: grid's `circleGrob()`, its colours carrying each point's colour and alpha as
  # ggplot2's `alpha()` and `fill_alpha()` give them. R's graphics engine draws a point's round
  # shapes so: shape 19, the solid circle that is ggplot2's default point, outlined and filled in
  # its colour; 16 filled alone; 1 outlined alone; 21 outlined in its colour and filled in its fill.

  @enforce_keys [:x, :y, :radius, :stroke_width, :color, :color_opacity, :fill, :fill_opacity]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          x: [float()],
          y: [float()],
          radius: [float()],
          stroke_width: float(),
          color: [String.t() | :none],
          color_opacity: [float()],
          fill: [String.t() | :none],
          fill_opacity: [float()]
        }
end
